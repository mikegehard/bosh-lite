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

vagrant box add bosh-lite-virtualbox-ubuntu-14-04-0.box --name boshlite-ubuntu1404 --force || true
vagrant up local --provider=virtualbox

./bin/add-route || true

rm -rf bosh || true
git clone https://github.com/cloudfoundry/bosh.git

(
  cd bosh
  git submodule update --init --recursive
  bundle install

  bundle exec bosh -n target 192.168.50.4:25555

  wget -nv -N https://s3.amazonaws.com/bosh-jenkins-artifacts/bosh-stemcell/warden/latest-bosh-stemcell-warden.tgz
  sleep 30

  # a pre upload so we stopped early when director dies etc.
  bundle exec bosh -u admin -p admin -n upload stemcell ./latest-bosh-stemcell-warden.tgz || sleep 30

  DIRECTOR_UUID=$(bosh -u admin -p admin status | grep UUID | awk '{print $2}')
  echo $DIRECTOR_UUID

  # Create bat.spec
  cat > bat.spec << EOF
---
cpi: warden
properties:
  static_ip: 10.244.0.2
  uuid: $DIRECTOR_UUID
  pool_size: 1
  stemcell:
    name: bosh-warden-boshlite-ubuntu-trusty-go_agent
    version: latest
  instances: 1
  mbus: nats://nats:nats-password@10.254.50.4:4222
EOF

  export BAT_DEPLOYMENT_SPEC=$PWD/bat.spec
  export BAT_DIRECTOR=192.168.50.4
  export BAT_DNS_HOST=192.168.50.4
  export BAT_STEMCELL=$PWD/latest-bosh-stemcell-warden.tgz
  export BAT_VCAP_PASSWORD=c1oudc0w
  export BAT_INFRASTRUCTURE=warden

  cd bat
  bundle exec rake bat
)

#s3cmd put -P ./*.box s3://bosh-lite-build-artifacts/bosh-lite/${CANDIDATE_BUILD_NUMBER}/
