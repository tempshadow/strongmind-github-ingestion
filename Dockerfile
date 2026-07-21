FROM ruby:3.3.0-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install --deployment --without development test

FROM ruby:3.3.0-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    libpq5 \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m app && chown -R app:app /app
USER app

COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --chown=app:app . .

ENV PATH="/usr/local/bundle/bin:$PATH"
ENV RAILS_ENV=production

EXPOSE 3000

ENTRYPOINT ["./bin/docker-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
