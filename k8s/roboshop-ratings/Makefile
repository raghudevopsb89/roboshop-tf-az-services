.PHONY: build run unit-test integration-test coverage docker-build db-init clean

build:
	pip install -r requirements.txt

run:
	MYSQL_HOST=localhost python app.py

unit-test:
	pytest -m "not integration"

integration-test:
	pytest -m integration

coverage:
	pytest -m "not integration" --cov=. --cov-report=xml --cov-report=term-missing

docker-build:
	env
	docker build -t raghudevopsb89.azurecr.io/roboshop-ratings:${GITHUB_SHA} .

docker-push:
	docker push raghudevopsb89.azurecr.io/roboshop-ratings:${GITHUB_SHA}

docker-scan:
	trivy image raghudevopsb89.azurecr.io/roboshop-ratings:${GITHUB_SHA} --exit-code 1 --ignore-unfixed -s HIGH,CRITICAL

db-init:
	mysql -h $${MYSQL_HOST:-localhost} -u root -pRoboShop@1 < db/app-user.sql
	mysql -h $${MYSQL_HOST:-localhost} -u root -pRoboShop@1 < db/schema.sql

clean:
	find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true

sonar_token := $(shell az keyvault secret show --name sonarqube-token --vault-name roboshopb89 --query "value" -o tsv)

sonar-scan:
	echo /home/runner/sonar-scanner-7.1.0.4889-linux-x64/bin/sonar-scanner -Dsonar.projectKey=roboshop-ratings -Dsonar.host.url=http://10.1.0.46:9000 -Dsonar.token=$(sonar_token) -Dsonar.qualitygate.wait=true -Dsonar.python.coverage.reportPaths=coverage.xml
