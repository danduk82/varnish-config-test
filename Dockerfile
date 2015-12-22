FROM nginx:latest
#RUN apt-get update
#RUN apt-get install -y tar git curl python-pip
COPY static-html-directory /usr/share/nginx/html


EXPOSE 80

# Set the default command to execute
# when creating a new container
#CMD service nginx start
