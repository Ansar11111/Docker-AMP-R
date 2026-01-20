FROM php:8.2-apache

# Build-time arguments
ARG PHP_MEMORY_LIMIT=256M
ARG PHP_MAX_EXECUTION_TIME=30
ARG PHP_UPLOAD_MAX_FILESIZE=20M
ARG PHP_POST_MAX_SIZE=20M

# Use production PHP settings
RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libwebp-dev \
        libzip-dev \
        zlib1g-dev \
        libonig-dev \
        curl \
        sendmail \
        git \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
# GD
RUN docker-php-ext-configure gd \
        --with-jpeg \
        --with-freetype \
        --with-webp \
    && docker-php-ext-install -j$(nproc) gd

# MySQL PDO
RUN docker-php-ext-install pdo pdo_mysql mysqli zip mbstring

# Redis via PECL
RUN printf "\n" | pecl install redis \
    && docker-php-ext-enable redis

# Configure PHP
RUN echo "memory_limit = ${PHP_MEMORY_LIMIT}" >> /usr/local/etc/php/conf.d/docker-php-memory-limit.ini \
    && echo "max_execution_time = ${PHP_MAX_EXECUTION_TIME}" >> /usr/local/etc/php/conf.d/docker-php-max-execution-time.ini \
    && echo "upload_max_filesize = ${PHP_UPLOAD_MAX_FILESIZE}" >> /usr/local/etc/php/conf.d/docker-php-upload-max-filesize.ini \
    && echo "post_max_size = ${PHP_POST_MAX_SIZE}" >> /usr/local/etc/php/conf.d/docker-php-post-max-size.ini

# Configure Apache
RUN a2enmod rewrite headers ssl remoteip \
    && sed -i 's/ServerTokens OS/ServerTokens Prod/' /etc/apache2/conf-available/security.conf \
    && sed -i 's/ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf

# Copy Apache configuration (prevents Windows mount issues)
# Make sure you have these files in ./Configuration/ locally
COPY Configuration/apache-host.conf /etc/apache2/sites-available/website.conf
COPY Configuration/apache-security.conf /etc/apache2/conf-enabled/security-hardening.conf

# Enable the custom site at build time
RUN a2dissite 000-default \
    && a2ensite website \
    && apachectl -t

# Create non-root user and set permissions
RUN useradd -r -u 1000 -g www-data webuser \
    && mkdir -p /var/log/php \
    && chown -R webuser:www-data /var/log/php \
    && chmod 755 /var/log/php \
    && chown -R webuser:www-data /var/www/html \
    && chmod -R 750 /var/www/html

# Switch to non-root user
USER webuser

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Verify PHP extensions and Apache modules
RUN echo ">>> Verifying PHP extensions..." \
    && php -m | grep -E 'gd|pdo|pdo_mysql|mysqli|zip|mbstring|redis' \
    || (echo "One or more PHP extensions failed to install!" && exit 1) \
    && echo ">>> Verifying Apache modules..." \
    && apache2ctl -M | grep -E 'rewrite_module|headers_module|ssl_module|remoteip_module' \
    || (echo "One or more Apache modules failed to enable!" && exit 1) \
    && echo ">>> All extensions and modules installed successfully!"
