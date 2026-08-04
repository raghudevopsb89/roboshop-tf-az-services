FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npm run build

FROM nginx
RUN apt-get update && \
    apt-get install --only-upgrade -y libtiff6 && \
    rm -rf /var/lib/apt/lists/*
RUN rm -rf /etc/nginx/conf.d
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/out /usr/share/nginx/html
EXPOSE 80
