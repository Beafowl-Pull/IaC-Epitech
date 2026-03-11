.PHONY: build run test lint docker-build docker-push helm-lint deploy-staging deploy-prod

IMAGE_REPO ?= gcr.io/YOUR_PROJECT/task-manager
IMAGE_TAG  ?= $(shell git rev-parse --short HEAD)

build:
	go build -o bin/task-manager ./main.go

run:
	docker-compose up --build

down:
	docker-compose down -v

test:
	go test ./... -v -race

lint:
	go vet ./...
	test -z "$(shell gofmt -l .)"

docker-build:
	docker build -t $(IMAGE_REPO):$(IMAGE_TAG) -t $(IMAGE_REPO):latest .

docker-push: docker-build
	docker push $(IMAGE_REPO):$(IMAGE_TAG)
	docker push $(IMAGE_REPO):latest

helm-lint:
	helm lint ./helm/task-manager --set secrets.jwtSecret=test \
	  --set secrets.dbPassword=test --set secrets.apiPassword=test

helm-template:
	helm template task-manager ./helm/task-manager \
	  --set secrets.jwtSecret=test \
	  --set secrets.dbPassword=test \
	  --set secrets.apiPassword=test

deploy-staging:
	ENV=staging bash scripts/deploy.sh staging

deploy-prod:
	ENV=prod bash scripts/deploy.sh prod
