FROM debian:jessie

# add C2C repository for varnish

RUN apt-get update -y
RUN apt-get install wget -y
COPY apt /etc/apt
RUN wget http://pkg.camptocamp.net/packages-c2c-key.gpg
RUN apt-key add packages-c2c-key.gpg

# install varnish
RUN apt-get update -y
RUN apt-get install -y varnish

## install vcl files and compile VCL
#COPY varnish /etc/varnish
#RUN /usr/share/varnish/reload-vcl

EXPOSE 80

# Set the default command to execute
# when creating a new container
CMD systemctl start varnish
