#!/bin/bash
set -Eeuo pipefail

exec > >(tee -a /var/log/shopease-user-data.log) 2>&1

echo "Starting Shopease website deployment..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends nginx git ca-certificates

rm -rf /tmp/Responsive-Food-Restaurant
if ! git clone --depth 1 https://github.com/yadekola/Responsive-Food-Restaurant.git /tmp/Responsive-Food-Restaurant; then
  echo "ERROR: Git clone failed for the application source repository."
  exit 1
fi

if [ ! -f /tmp/Responsive-Food-Restaurant/index.html ]; then
  echo "ERROR: index.html was not found in the repository root."
  exit 1
fi

install -d -m 755 /var/www/html
find /var/www/html -mindepth 1 -maxdepth 1 -exec rm -rf {} +
cp -a /tmp/Responsive-Food-Restaurant/. /var/www/html/
rm -rf /var/www/html/.git

chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;

systemctl enable --now nginx
systemctl restart nginx

echo "Shopease website deployment completed."
