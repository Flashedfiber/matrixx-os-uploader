#!/usr/bin/env bash

echo "Setting up Matrixx-OS uploader..."

chmod +x nc.sh

if [[ ! -f .env ]]; then
    cp .env.example .env
    echo "Created .env file. Please edit it."
fi

echo "Done."
