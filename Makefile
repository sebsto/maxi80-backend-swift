# API Configuration
API_GATEWAY_URL = https://sy50d5rbgh.execute-api.eu-central-1.amazonaws.com/Prod
API_KEY_ID = ll9kmivjdb
AWS_REGION = eu-central-1
AWS_PROFILE = maxi80

format:
	swift format -i -r Package.swift Sources Tests

build:
	swift package --allow-network-connections docker archive --disable-docker-image-update --products Maxi80Lambda
	cp .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/Maxi80Lambda/bootstrap .aws-sam/build/Maxi80Lambda/bootstrap  
	cp template.yaml .aws-sam/build/template.yaml
	
test:
	swift test

deploy:
	sam deploy --config-env dev

call-station:
	$(eval API_KEY := $(shell aws apigateway get-api-key --api-key $(API_KEY_ID) --include-value --region $(AWS_REGION) --profile $(AWS_PROFILE) --query "value" --output text))
	@curl -X GET \
  "$(API_GATEWAY_URL)/station" \
  -H "x-api-key: $(API_KEY)" \
  -H "Accept: application/json"

call-search:
	$(eval API_KEY := $(shell aws apigateway get-api-key --api-key $(API_KEY_ID) --include-value --region $(AWS_REGION) --profile $(AWS_PROFILE) --query "value" --output text))
	$(eval SEARCH_TERM := $(shell echo 'Pink Floyd - The wall' | jq -sRr @uri))
	@curl -X GET \
  "$(API_GATEWAY_URL)/search?term=$(SEARCH_TERM)" \
  -H "x-api-key: $(API_KEY)" \
  -H "Accept: application/json"

# Helper target to get just the API key
get-api-key:
	@aws apigateway get-api-key --api-key $(API_KEY_ID) --include-value --region $(AWS_REGION) --profile $(AWS_PROFILE) --query "value" --output text

BUILD_DIR := .aws-sam/build

.PHONY: build-%

build-%:
	@echo "Building Maxi80 Lambda..."
	@echo "ARTIFACTS_DIR is: $(ARTIFACTS_DIR)"
	swift package --allow-network-connections docker archive --disable-docker-image-update --products Maxi80Lambda
	cp .build/plugins/AWSLambdaPackager/outputs/AWSLambdaPackager/Maxi80Lambda/bootstrap $(ARTIFACTS_DIR)/
	@echo "Build for all Lambdas complete."

prepare-sam-build:
	find . -type l ! -exec test -e {} \; -delete
