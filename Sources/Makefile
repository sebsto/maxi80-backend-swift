format:
	swift format -i -r Package.swift Sources
build:
	swift package archive --allow-network-connections docker --disable-docker-image-update --target Maxi80Lambda
deploy:
	sam deploy --profile maxi80 --region eu-central-1 --stack-name Maxi80Backend-2025 --resolve-s3

BUILD_DIR := .aws-sam/build

.PHONY: build-%

build-%:
	@echo "Building Maxi80 Lambda..."; \
	swift package --allow-network-connections docker archive --disable-docker-image-update --products Maxi80Lambda; \
	cp .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/Maxi80Lambda/bootstrap $(ARTIFACTS_DIR)
	echo "Build for all Lambdas complete."; 

prepare-sam-build:
	find . -type l ! -exec test -e {} \; -delete
