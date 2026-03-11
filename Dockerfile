#FROM redhat/ubi9-minimal:latest
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

ARG USER_NAME="bob"
ARG USER_UID=1001
ARG HANDOFF_GROUP_NAME="handoff"
ARG HANDOFF_GID=1002

RUN microdnf makecache \
	&& microdnf install -y bash git gnupg openssh-clients

RUN useradd --uid $USER_UID $USER_NAME \
	&& groupadd --gid $HANDOFF_GID $HANDOFF_GROUP_NAME \
	&& usermod -aG $HANDOFF_GROUP_NAME $USER_NAME \
	&& id $USER_NAME

ADD src/ /usr/local/bin

USER $USER_NAME
