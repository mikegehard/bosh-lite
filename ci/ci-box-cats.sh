set -x
set -e

export TERM=xterm
export PATH=/var/lib/jenkins/.rbenv/shims:/var/lib/jenkins/.rbenv/bin:/usr/local/bin:/usr/bin:/bin:$PATH
export RBENV_VERSION=1.9.3-p547

CUD=$(pwd)
export TMPDIR=$CUD

cleanup()
{
  cd $CUD
  vagrant destroy -f
}

trap cleanup EXIT

echo $CANDIDATE_BUILD_NUMBER

vagrant destroy local -f
rm -rf /var/lib/jenkins/.bosh_cache/* || true

vagrant box add bosh-lite-virtualbox-ubuntu-14-04-0.box --name b boshlite-ubuntu1404 --force || true
vagrant up local --provider=virtualbox

wget -nv -N https://s3.amazonaws.com/bosh-jenkins-artifacts/bosh-stemcell/warden/latest-bosh-stemcell-warden.tgz
sleep 30

$(dirname $0)/../bin/add-route

rm -rf bosh || true
git clone https://github.com/cloudfoundry/bosh.git
git submodule update --init --recursive
bundle install

(
  cd bosh
  bundle exec bosh -n target 192.168.50.4:25555

  # a pre upload so we stopped early when director dies etc.
  bundle exec bosh -u admin -p admin -n upload stemcell ./latest-bosh-stemcell-warden.tgz || sleep 30
  export BUNDLE_GEMFILE=$PWD/Gemfile
)

rm -rf cf-release || true
git clone https://github.com/cloudfoundry/cf-release.git

(
   cd cf-release
   ref=${CF_VERSION:-"$last"}
   git checkout v${ref}
   git submodule update --init --recursive
   cmd="bundle exec bosh -u admin -p admin -n upload release releases/cf-${ref}.yml"
   $cmd || (sleep 120; bundle exec bosh -u admin -p admin releases | grep cf ) || $cmd
)

CF_RELEASE_DIR=../cf-release $(dirname $0)/../make_manifest_spiff

bundle exec bosh -u admin -p admin -n deploy || bosh -u admin -p admin -n deploy
sleep 120

cat > integration_config.json <<EOF
{
  "api": "api.10.244.0.34.xip.io",
  "admin_user": "admin",
  "admin_password": "admin",
  "apps_domain": "10.244.0.34.xip.io",
  "skip_ssl_validation": true
}
EOF

export CF_TRACE_BASENAME=cf_trace_

export CONFIG=$PWD/integration_config.json
rm -rf cats
mkdir -p cats
export GOPATH=$PWD/cats

go get -d github.com/cloudfoundry/cf-acceptance-tests || true

(
  cd $GOPATH/src/github.com/cloudfoundry/cf-acceptance-tests
  ./bin/test -nodes=2 || ./bin/test -nodes=2
)
