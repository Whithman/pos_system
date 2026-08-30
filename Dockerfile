FROM php:8.3-apache

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev libcurl4-openssl-dev libpng-dev libjpeg62-turbo-dev libwebp-dev \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install pdo_pgsql curl gd opcache \
    && a2enmod rewrite deflate expires headers \
    && rm -rf /var/lib/apt/lists/*

# PERFORMANCE FIX: without this, PHP was re-parsing and re-compiling the
# entire ~20,000-line index.php from scratch on EVERY single request/click.
# OPcache keeps the compiled bytecode in shared memory across requests, so
# only the first request after a deploy pays that cost.
RUN { \
    echo 'opcache.enable=1'; \
    echo 'opcache.enable_cli=0'; \
    echo 'opcache.memory_consumption=192'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=10000'; \
    # validate_timestamps=1 with a short revalidate_freq means opcache still
    # notices new deploys automatically (no manual cache-clear step needed),
    # while not re-stat'ing the file on every single request like default 2s.
    echo 'opcache.validate_timestamps=1'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.save_comments=0'; \
    echo 'realpath_cache_size=4096K'; \
    echo 'realpath_cache_ttl=600'; \
    } > /usr/local/etc/php/conf.d/opcache-perf.ini

# PERFORMANCE FIX: gzip/deflate compression. index.php sends 130-240KB of
# HTML+inline CSS+inline JS on every single page click — that's the file
# actually being downloaded over the network on every navigation. Text
# compresses ~75-85%, so this alone cuts the biggest chunk of "wait time"
# on a mobile connection, on top of the OPcache fix above.
RUN { \
    echo '<IfModule mod_deflate.c>'; \
    echo '  AddOutputFilterByType DEFLATE text/html text/css text/plain text/xml application/xml application/javascript application/json'; \
    echo '  DeflateCompressionLevel 6'; \
    echo '</IfModule>'; \
    echo '<IfModule mod_expires.c>'; \
    echo '  ExpiresActive On'; \
    echo '  ExpiresByType image/png "access plus 30 days"'; \
    echo '  ExpiresByType image/webp "access plus 30 days"'; \
    echo '  ExpiresByType image/jpeg "access plus 30 days"'; \
    echo '  ExpiresByType text/css "access plus 7 days"'; \
    echo '  ExpiresByType application/javascript "access plus 7 days"'; \
    echo '</IfModule>'; \
    } > /etc/apache2/conf-available/perf.conf \
    && a2enconf perf

WORKDIR /var/www/html
COPY . /var/www/html/

RUN mkdir -p /var/www/html/uploads/products \
    && chown -R www-data:www-data /var/www/html/uploads

EXPOSE 80

# Render supplies PORT at runtime (normally 10000). Apache must listen on
# that port for Render's health checks and proxy to reach the container.
# ServerName is set once here (rather than sed'd at boot) purely to silence
# the "Could not reliably determine the server's fully qualified domain
# name" warning on every boot — cosmetic, not a performance fix.
CMD ["sh", "-c", "PORT=\"${PORT:-10000}\"; sed -i \"s/^Listen 80$/Listen ${PORT}/\" /etc/apache2/ports.conf; sed -i \"s#<VirtualHost \\*:80>#<VirtualHost *:${PORT}>#\" /etc/apache2/sites-available/000-default.conf; echo \"ServerName localhost\" >> /etc/apache2/apache2.conf; exec apache2-foreground"]
