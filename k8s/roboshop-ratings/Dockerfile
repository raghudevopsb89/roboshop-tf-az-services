FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8006
ENV NEW_RELIC_APP_NAME=roboshop-ratings
ENV NEW_RELIC_DISTRIBUTED_TRACING_ENABLED=true
ENV NEW_RELIC_LOG=stdout
CMD ["newrelic-admin", "run-program", "gunicorn", "-b", "0.0.0.0:8006", "-w", "2", "--graceful-timeout", "25", "app:app"]

#
