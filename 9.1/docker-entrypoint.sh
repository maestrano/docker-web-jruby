#!/bin/bash
set -e

# Go to app directory
cd /app

# Set default environment variables
export FOREMAN_OPTS=${FOREMAN_OPTS:-""}
export RACK_ENV=${RACK_ENV:-production}
export RAILS_ENV=${RAILS_ENV:-production}
export RAILS_LOG_TO_STDOUT=${RAILS_LOG_TO_STDOUT:-true}
export GIT_BRANCH=${GIT_BRANCH:-master}

# Configure bundler to use gemstash server if specified
if [ -n "$GEMSTASH_SERVER" ]; then
  bundle config mirror.https://rubygems.org $GEMSTASH_SERVER
  bundle config mirror.https://rubygems.org.fallback_timeout 3
fi

# Clone app from git
if [ -n "$GIT_URL" ] && [ -n "$GIT_BRANCH" ]; then
  [ -d /app/.git ] || git clone --branch "$GIT_BRANCH" --depth 50 $GIT_URL /app
  [ -n "$GIT_COMMIT_ID" ] && git checkout -qf $GIT_COMMIT_ID

# Download app from S3
elif [ -n "$S3_URI" ] && [ -n "$S3_ACCESS_KEY_ID" ] && [ -n "$S3_SECRET_ACCESS_KEY" ]; then
  AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY aws s3 cp $S3_URI ./
  archive_file=$(ls)
  tar xf $archive_file
  rm -f $archive_file
fi

# Run deploy hook
if [ -f /app/.deploy-hook ]; then
  [ "$NO_HOOK" == "true" ] || bash /app/.deploy-hook
fi

# Run bundler
if [ -f /app/Gemfile ]; then
  # Install all required gems
  [ "$NO_BUNDLE" == "true" ] || bundle install --without development test
fi

# Run rails specific tasks
if [ -f /app/config/application.rb ]; then
  # Load schema (you should unset this var afterwards)
  [ "$RAILS_LOAD_SCHEMA" == "true" ] && bundle exec rake db:schema:load

  # Migrate database
  [ "$NO_MIGRATE" == "true" ] || bundle exec rake db:migrate

  # Pre-compile assets
  [ "$NO_COMPILE" == "true" ] || bundle exec rake assets:precompile
fi

# Nginx configuration
if [ ! "$NO_NGINX" == "true" ] && [ -f /app/nginx.conf ]; then
  rm -f /etc/nginx/sites-enabled/*
  cp -p /app/nginx.conf /etc/nginx/sites-enabled/
fi

# Update ownership
chown -R www-data:www-data /app /var/log/app

# Run post-deploy hook
if [ -f /app/.post-deploy-hook ]; then
  [ "$NO_HOOK" == "true" ] || bash /app/.post-deploy-hook
fi

# Perform command - default is "foreman start" (see Dockerfile)
exec "$@"
