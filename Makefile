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
	$(eval API_KEY := $(shell aws apigateway get-api-key --api-key ll9kmivjdb --include-value --region eu-central-1 --profile maxi80 --query "value" --output text))
	@curl -X GET \
  "https://6vcu20yo5c.execute-api.eu-central-1.amazonaws.com/Prod/station" \
  -H "x-api-key: $(API_KEY)" \
  -H "Accept: application/json"

call-search:
	$(eval API_KEY := $(shell aws apigateway get-api-key --api-key ll9kmivjdb --include-value --region eu-central-1 --profile maxi80 --query "value" --output text))
	$(eval SEARCH_TERM := $(shell echo 'Pink Floyd - The wall' | jq -sRr @uri))
	@curl -X GET \
  "https://6vcu20yo5c.execute-api.eu-central-1.amazonaws.com/Prod/search?term=$(SEARCH_TERM)" \
  -H "x-api-key: $(API_KEY)" \
  -H "Accept: application/json"

# Helper target to get just the API key
get-api-key:
	@aws apigateway get-api-key --api-key ll9kmivjdb --include-value --region eu-central-1 --profile maxi80 --query "value" --output text

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
