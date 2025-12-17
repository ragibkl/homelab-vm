#!/bin/sh

# Generate 48-character token
openssl rand -base64 48 | tr -d "=+/" | cut -c1-48
