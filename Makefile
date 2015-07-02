
.PHONY: all sles-11 debian-8 debian-7 debian-6 ubuntu-14 ubuntu-12 centos-7 centos-6 centos-5

all: sles-11 debian-8 debian-7 debian-6 ubuntu-14 ubuntu-12 centos-7 centos-6 centos-5

debian-8:
	docker build --file=src/dockerfiles/debian-8 --force-rm=true --pull=true --rm=true --tag=debian_base:8 --tag=debian_base:jessie src

debian-7:
	docker build --file=src/dockerfiles/debian-7 --force-rm=true --pull=true --rm=true --tag=debian_base:7 --tag=debian_base:wheezy src

debian-6:
	docker build --file=src/dockerfiles/debian-6 --force-rm=true --pull=true --rm=true --tag=debian_base:6 --tag=debian_base:squeeze src

ubuntu-14:
	docker build --file=src/dockerfiles/ubuntu-14 --force-rm=true --pull=true --rm=true --tag=ubuntu_base:14 --tag=ubuntu_base:trusty src

ubuntu-12:
	docker build --file=src/dockerfiles/ubuntu-12 --force-rm=true --pull=true --rm=true --tag=ubuntu_base:12 --tag=ubuntu_base:precise src

centos-7:
	docker build --file=src/dockerfiles/centos-7 --force-rm=true --pull=true --rm=true --tag=centos_base:7 src

centos-6:
	docker build --file=src/dockerfiles/centos-6 --force-rm=true --pull=true --rm=true --tag=centos_base:6 src

centos-5:
	docker build --file=src/dockerfiles/centos-5 --force-rm=true --pull=true --rm=true --tag=centos_base:5 src

sles-11:
	docker build --file=src/dockerfiles/sles-11 --force-rm=true --pull=true --rm=true --tag=sles_base:11 src
