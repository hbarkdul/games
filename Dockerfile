FROM nginx:alpine
ARG APP
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY ${APP}/ /usr/share/nginx/html/
