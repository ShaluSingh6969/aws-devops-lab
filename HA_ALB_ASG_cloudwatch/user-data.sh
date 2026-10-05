#!/bin/bash
dnf install -y nginx
systemctl enable nginx
systemctl start nginx

HOSTNAME=$(hostname)

cat > /usr/share/nginx/html/index.html <<HTML
<html>
  <body>
    <h1>Day 5 HA Lab</h1>
    <p>Served by: $HOSTNAME</p>
  </body>
</html>
HTML
