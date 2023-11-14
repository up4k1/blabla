#!/bin/bash

# Установка Docker
echo "Установка Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Установка Docker Compose
echo "Установка Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Запрос данных от пользователя
read -p "Введите ваш email: " email
read -p "Введите ваш домен без https, например google.com: " domain
read -p "Введите ваш GeoLite ключ: " geolite_key
read -p "Введите вашу временную зону, например Europe/Samara: " TZ
read -sp "Введите пароль для базы данных: " db_password
echo
read -p "Введите имя пользователя для админ-панели: " http_user
read -sp "Введите пароль для админ-панели: " http_password
echo

# Генерация захешированного пароля для HTTP Basic Auth
hashed_password=$(openssl passwd -apr1 "$http_password")

# Создание файла docker-compose.yml
cat > docker-compose.yml <<EOF
version: "3"

services:
  traefik:
    image: traefik:v2.5
    container_name: traefik
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./letsencrypt:/letsencrypt"
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.myresolver.acme.tlschallenge=true"
      - "--certificatesresolvers.myresolver.acme.email=$email"
      - "--certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json"

  shlink:
    image: shlinkio/shlink:stable
    restart: always
    container_name: shlink-backend
    environment:
      - TZ=$TZ
      - DEFAULT_DOMAIN=$domain
      - IS_HTTPS_ENABLED=true
      - GEOLITE_LICENSE_KEY=$geolite_key
      - DB_DRIVER=maria
      - DB_USER=shlink
      - DB_NAME=shlink
      - DB_PASSWORD=$db_password
      - DB_HOST=database
    depends_on:
      - database
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.shlink.rule=Host(\`$domain\`)"
      - "traefik.http.routers.shlink.entrypoints=websecure"
      - "traefik.http.routers.shlink.tls.certresolver=myresolver"

  database:
    image: mariadb:10.8
    restart: always
    container_name: shlink-database
    environment:
      - MARIADB_ROOT_PASSWORD=$db_password
      - MARIADB_DATABASE=shlink
      - MARIADB_USER=shlink
      - MARIADB_PASSWORD=$db_password
    volumes:
      - /home/docker/shlink:/var/lib/mysql

  shlink-web-client:
    image: shlinkio/shlink-web-client
    restart: always
    container_name: shlink-gui
    volumes:
      - /home/docker/shlink/servers.json:/usr/share/nginx/html/servers.json
    depends_on:
      - shlink
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.shlink-gui.rule=Host(\`$domain\`)"
      - "traefik.http.routers.shlink-gui.entrypoints=websecure"
      - "traefik.http.routers.shlink-gui.tls.certresolver=myresolver"
      - "traefik.http.middlewares.shlink-gui-auth.basicauth.users=$http_user:\$hashed_password"
    ports:
      - 8081:80

volumes:
  letsencrypt:
EOF

# Запуск Docker Compose
docker-compose up -d
