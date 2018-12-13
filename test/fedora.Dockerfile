FROM fedora:latest

ENV GITDIR /etc/.xfilter
ENV SCRIPTDIR /opt/xfilter

RUN mkdir -p $GITDIR $SCRIPTDIR /etc/xfilter
ADD . $GITDIR
RUN cp $GITDIR/advanced/Scripts/*.sh $GITDIR/gravity.sh $GITDIR/xfilter $GITDIR/automated\ install/*.sh $SCRIPTDIR/
ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$SCRIPTDIR

RUN true && \
    chmod +x $SCRIPTDIR/*

ENV PH_TEST true

#sed '/# Start the installer/Q' /opt/xfilter/basic-install.sh > /opt/xfilter/stub_basic-install.sh && \
