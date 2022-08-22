#!/bin/bash
sudo yum install httpd php -y
sudo echo '<h1>Hello Hele World!</h1>' > ~/index.html
sudo cp ~/index.html /var/www/html/
sudo rm -f /etc/httpd/conf.d/welcome.conf
sudo systemctl start httpd
sudo systemctl enable httpd
