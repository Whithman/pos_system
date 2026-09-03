FROM php:8.3-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev libcurl4-openssl-dev libpng-dev libjpeg62-turbo-dev libwebp-dev \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install pdo_pgsql curl gd \
    && a2enmod rewrite \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html
COPY . /var/www/html/

RUN mkdir -p /var/www/html/uploads/products \
    && chown -R www-data:www-data /var/www/html/uploads

EXPOSE 80

# Render supplies PORT at runtime (normally 10000). Apache must listen on
# that port for Render's health checks and proxy to reach the container.
CMD ["sh", "-c", "PORT=\"${PORT:-10000}\"; sed -i \"s/^Listen 80$/Listen ${PORT}/\" /etc/apache2/ports.conf; sed -i \"s#<VirtualHost \\*:80>#<VirtualHost *:${PORT}>\\n<Directory /var/www/html>\\nAllowOverride All\\n</Directory>#\" /etc/apache2/sites-available/000-default.conf; exec apache2-foreground"]
