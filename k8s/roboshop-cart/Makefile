.PHONY: build run unit-test coverage integration-test docker-build clean

build:
	npm install

run:
	REDIS_HOST=localhost CATALOGUE_URL=http://localhost:8002 node server.js

unit-test:
	npm test

coverage:
	npm run test:coverage

integration-test:
	npm run test:integration

docker-build:
	env
	docker build -t raghudevopsb89.azurecr.io/roboshop-cart:${GITHUB_SHA} .

docker-scan:
	trivy image raghudevopsb89.azurecr.io/roboshop-cart:${GITHUB_SHA} --exit-code 1 --ignore-unfixed -s HIGH,CRITICAL

docker-push:
	docker push raghudevopsb89.azurecr.io/roboshop-cart:${GITHUB_SHA}

clean:
	rm -rf node_modules

sonar_token := $(shell az keyvault secret show --name sonarqube-token --vault-name roboshopb89 --query "value" -o tsv)

sonar-scan:
	echo /home/runner/sonar-scanner-7.1.0.4889-linux-x64/bin/sonar-scanner -D sonar.projectKey=roboshop-cart -Dsonar.host.url=http://10.1.0.46:9000 -Dsonar.token=$(sonar_token) -Dsonar.qualitygate.wait=true -D sonar.javascript.lcov.reportPaths=coverage/lcov.info

