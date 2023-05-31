#!/bin/bash

# Instalação de dependências
sudo apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg

sudo LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
sudo add-apt-repository ppa:redislabs/redis -y

# Instalação do MariaDB (apenas para o Linux 20.04 ou inferior)
if [[ $(lsb_release -rs) < "21.04" ]]; then
    curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
fi

# Atualização do sistema e instalação de pacotes
sudo apt update
sudo apt -y install php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server nano cron
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

# Preparação do diretório do projeto
sudo mkdir -p /var/www/jexactyl
cd /var/www/jexactyl

# Download e extração do painel
sudo curl -Lo panel.tar.gz https://github.com/Next-Panel/Jexactyl-BR/releases/latest/download/panel.tar.gz
sudo tar -xzvf panel.tar.gz
sudo chmod -R 755 storage/* bootstrap/cache/

# Configuração do banco de dados
sudo mysql -u root -p

# Solicitar senha ao usuário
read -s -p "Digite a senha do MySQL: " mysql_password
echo

# Executar comandos SQL
echo "CREATE USER 'jexactyl'@'127.0.0.1' IDENTIFIED BY '${mysql_password}';" | sudo mysql -u root -p
echo "CREATE DATABASE panel;" | sudo mysql -u root -p
echo "GRANT ALL PRIVILEGES ON panel.* TO 'jexactyl'@'127.0.0.1' WITH GRANT OPTION;" | sudo mysql -u root -p
echo "exit" | sudo mysql -u root -p

# Configuração do ambiente do Laravel
sudo cp .env.example .env
sudo composer install --no-dev --optimize-autoloader
sudo php artisan key:generate --force
sudo php artisan p:environment:setup
sudo php artisan p:environment:database
sudo php artisan migrate --seed --force
sudo php artisan p:user:make

# Configuração do usuário e permissões
sudo chown -R www-data:www-data /var/www/jexactyl/*

# Configuração das tarefas agendadas
sudo crontab -e

# Após abrir o arquivo, cole as seguintes linhas no final e salve:
# * * * * * php /var/www/jexactyl/artisan schedule:run >> /dev/null 2>&1
# 0 0 * * * php /var/www/jexactyl/artisan p:schedule:renewal >> /dev/null 2>&1

# Configuração do serviço do painel
sudo nano /etc/systemd/system/panel.service

# Cole o seguinte texto no arquivo criado e salve:
# # Jexactyl Queue Worker File
# # ----------------------------------
# 
# [Unit]
# Description=Jexactyl Queue Worker
# 
# [Service]
# User=www-data
# Group=www-data
# Restart=always
# ExecStart=/usr/bin/php /var/www/jexactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
# StartLimitInterval=180
# StartLimitBurst=30
# RestartSec=5s
# 
# [Install]
# WantedBy=multi-user.target

# Habilitar e iniciar o serviço do painel
sudo systemctl enable --now panel.service
sudo systemctl enable --now redis-server

# Instalação do certbot e obtenção do certificado SSL
sudo apt install -y certbot python3-certbot-nginx

# Solicitar a URL do site do painel
read -p "Digite a URL do site do painel: " site_url

# Obter o certificado SSL
sudo certbot certonly --nginx -d "${site_url}"

# Remover configurações padrão do Nginx
sudo rm /etc/nginx/sites-available/default
sudo rm /etc/nginx/sites-enabled/default

# Configurar o arquivo de host do painel
sudo nano /etc/nginx/sites-available/panel.conf

# Cole o seguinte texto no arquivo criado e substitua <domain> pela URL do site:
# server {
#     listen 80;
#     server_name ${site_url};
#     return 301 https://$server_name$request_uri;
# }
# 
# server {
#     listen 443 ssl http2;
#     server_name ${site_url};
# 
#     root /var/www/jexactyl/public;
#     index index.php;
# 
#     access_log /var/log/nginx/jexactyl.app-access.log;
#     error_log  /var/log/nginx/jexactyl.app-error.log error;
# 
#     # allow larger file uploads and longer script runtimes
#     client_max_body_size 100m;
#     client_body_timeout 120s;
# 
#     sendfile off;
# 
#     # SSL Configuration
#     ssl_certificate /etc/letsencrypt/live/<domain>/fullchain.pem;
#     ssl_certificate_key /etc/letsencrypt/live/<domain>/privkey.pem;
#     ssl_session_cache shared:SSL:10m;
#     ssl_protocols TLSv1.2 TLSv1.3;
#     ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
#     ssl_prefer_server_ciphers on;
# 
#     add_header X-Content-Type-Options nosniff;
#     add_header X-XSS-Protection "1; mode=block";
#     add_header X-Robots-Tag none;
#     add_header Content-Security-Policy "frame-ancestors 'self'";
#     add_header X-Frame-Options DENY;
#     add_header Referrer-Policy same-origin;
# 
#     location / {
#         try_files $uri $uri/ /index.php?$query_string;
#     }
# 
#     location ~ \.php$ {
#         fastcgi_split_path_info ^(.+\.php)(/.+)$;
#         fastcgi_pass unix:/run/php/php8.1-fpm.sock;
#         fastcgi_index index.php;
#         include fastcgi_params;
#         fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
#         fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
#         fastcgi_param HTTP_PROXY "";
#         fastcgi_intercept_errors off;
#         fastcgi_buffer_size 16k;
#         fastcgi_buffers 4 16k;
#         fastcgi_connect_timeout 300;
#         fastcgi_send_timeout 300;
#         fastcgi_read_timeout 300;
#         include /etc/nginx/fastcgi_params;
#     }
# 
#     location ~ /\.ht {
#         deny all;
#     }
# }

# Criar link simbólico para o arquivo de host do painel
sudo ln -s /etc/nginx/sites-available/panel.conf /etc/nginx/sites-enabled/panel.conf

# Verificar a configuração do Nginx
sudo nginx -t

# Reiniciar o Nginx
sudo systemctl restart nginx

echo "A instalação do Jexactyl foi concluída com sucesso!"
