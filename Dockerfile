#
# K2HR3 Container Registration Sidecar
#
# Copyright 2019 Yahoo Japan Corporation.
#
# K2HR3 is K2hdkc based Resource and Roles and policy Rules, gathers
# common management information for the cloud.
# K2HR3 can dynamically manage information as "who", "what", "operate".
# These are stored as roles, resources, policies in K2hdkc, and the
# client system can dynamically read and modify these information.
#
# For the full copyright and license information, please view
# the license file that was distributed with this source code.
#
# AUTHOR:   Takeshi Nakatani
# CREATE:   Fri Sep 13 2019
# REVISION:
#

FROM docker.io/alpine:3.19.1

MAINTAINER antpickax

LABEL description="K2HR3 Container Registration Sidecar"
LABEL maintainer="antpickax <antpickax-support@mail.yahoo.co.jp>"

COPY k2hr3-k8s-init.sh /usr/local/bin/

RUN apk add -q --no-progress --no-cache curl

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
