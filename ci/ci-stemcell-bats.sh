set -x
set -e

export TERM=xterm
export PATH=/var/lib/jenkins/.rbenv/shims:/var/lib/jenkins/.rbenv/bin:/usr/local/bin:/usr/bin:/bin

CUD=$(pwd)

cleanup()
{
  cd $CUD/bosh-lite
  vagrant destroy -f
}

trap cleanup EXIT

rm $CUD/output/*.tgz || true

echo $CANDIDATE_BUILD_NUMBER
STEMCELL_PATH=$CUD/bosh-stemcell-$CANDIDATE_BUILD_NUMBER-warden-boshlite-ubuntu.tgz

rm -rf /var/lib/jenkins/.bosh_cache/* || true

vagrant box remove boshlite-ubuntu1404 virtualbox || true
vagrant up

sleep 30

rm -rf bosh || true
git clone https://github.com/cloudfoundry/bosh.git

(
  cd bosh

  git submodule update --init --recursive
  bundle install

  bundle exec bosh -n target 192.168.50.4:25555

  # a pre upload so we stopped early when director dies etc.
  bundle exec bosh -u admin -p admin -n upload stemcell $STEMCELL_PATH || sleep 30

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
    name: bosh-warden-boshlite-ubuntu
    version: latest
  instances: 1
  mbus: nats://nats:0b450ada9f830085e2cdeff6@10.42.49.80:4222
EOF


  export BAT_DEPLOYMENT_SPEC=$PWD/bat.spec
  export BAT_DIRECTOR=192.168.50.4
  export BAT_DNS_HOST=192.168.50.4
  export BAT_STEMCELL=$STEMCELL_PATH
  export BAT_VCAP_PASSWORD=c1oudc0w
  export BAT_INFRASTRUCTURE=warden

  cd bat
  bundle exec rake bat
)

cd $CUD
mkdir output || true
mv $STEMCELL_PATH $CUD/output/
