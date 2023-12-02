FROM nginx:1.25.1-alpine

# remove default nginx configuration
RUN rm /etc/nginx/nginx.conf /etc/nginx/conf.d/default.conf

# copy global nginx configuration
COPY ./config/nginx.conf /etc/nginx/nginx.conf
COPY ./config/root.conf.template /etc/nginx/templates/
COPY ./config/global /etc/nginx/global

# copy stage nginx configuration
ARG STAGE
COPY ./config/$STAGE/*.template /etc/nginx/templates/
COPY ./config/$STAGE/*.conf /etc/nginx/conf.d/

EXPOSE 80 443

# run nginx
CMD ["nginx", "-g", "daemon off;"]