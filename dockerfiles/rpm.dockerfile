#   Copyright 2018-2020 Docker Inc.

#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at

#       http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

ARG BUILD_IMAGE=centos:7
ARG BASE=centos
# Install golang since the package managed one probably is too old and ppa's don't cover all distros
ARG GOLANG_IMAGE

FROM ${GOLANG_IMAGE} AS golang

FROM alpine:3.10 AS git
RUN apk -u --no-cache add git

FROM git AS containerd-src
ARG REF=master
RUN git clone https://github.com/containerd/containerd.git /containerd
RUN git -C /containerd checkout "${REF}"

FROM git AS runc-src
ARG RUNC_REF=master
RUN git clone https://github.com/opencontainers/runc.git /runc
RUN git -C /runc checkout "${RUNC_REF}"

FROM golang AS go-md2man
ARG GOPROXY=direct
ARG GO111MODULE=on
ARG MD2MAN_VERSION=v2.0.0
RUN go get github.com/cpuguy83/go-md2man/v2/@${MD2MAN_VERSION}

FROM ${BUILD_IMAGE} AS redhat-base
RUN yum install -y yum-utils rpm-build git

FROM redhat-base AS rhel-base
ENV BUILDTAGS=no_btrfs

FROM redhat-base AS centos-base
# Overwrite repo that was failing on aarch64
RUN sed -i 's/altarch/centos/g' /etc/yum.repos.d/CentOS-Sources.repo

FROM redhat-base AS amzn-base

FROM redhat-base AS ol-base
ENV EXTRA_REPOS="--enablerepo=ol7_optional_latest"

FROM ${BUILD_IMAGE} AS fedora-base
RUN dnf install -y rpm-build git dnf-plugins-core

FROM ${BUILD_IMAGE} AS suse-base
# On older versions of Docker the path may not be explicitly set
# opensuse also does not set a default path in their docker images
RUN zypper -n install rpm-build git
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH}
RUN echo "%_topdir    /root/rpmbuild" > /root/.rpmmacros


FROM ${BASE}-base
RUN mkdir -p /go
ENV GOPATH=/go
ENV PATH="${PATH}:/usr/local/go/bin:${GOPATH}/bin"
ENV IMPORT_PATH=github.com/containerd/containerd
ENV GO_SRC_PATH="/go/src/${IMPORT_PATH}"

# Set up rpm packaging files
COPY common/ /root/rpmbuild/SOURCES/
COPY rpm/containerd.spec /root/rpmbuild/SPECS/containerd.spec
COPY scripts/build-rpm /build-rpm
COPY scripts/.rpm-helpers /.rpm-helpers
WORKDIR /root/rpmbuild

COPY --from=go-md2man      /go/bin/go-md2man /go/bin/go-md2man
COPY --from=golang         /usr/local/go/    /usr/local/go/
COPY --from=containerd-src /containerd/      /go/src/github.com/containerd/containerd/
COPY --from=runc-src       /runc/            /go/src/github.com/opencontainers/runc/

ARG PACKAGE
ENV PACKAGE=${PACKAGE:-containerd.io}
ENTRYPOINT ["/build-rpm"]
