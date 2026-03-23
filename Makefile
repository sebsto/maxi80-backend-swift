# SAM Configuration
SAM_STACK_NAME = Maxi80Backend-2025

# API Configuration
API_GATEWAY_URL = https://sy50d5rbgh.execute-api.eu-central-1.amazonaws.com/Prod
API_KEY_ID = ll9kmivjdb
AWS_REGION = eu-central-1
AWS_PROFILE = maxi80

format:
	swift format -i -r Package.swift Sources Tests

build:
	swift package --allow-network-connections docker archive --disable-docker-image-update --products IcecastMetadataCollector --products Maxi80Lambda
	
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

logs-maxi80:
	sam logs --stack-name $(SAM_STACK_NAME) --name Maxi80Lambda --region $(AWS_REGION) --profile $(AWS_PROFILE) --tail

logs-collector:
	sam logs --stack-name $(SAM_STACK_NAME) --name IcecastMetadataCollector --region $(AWS_REGION) --profile $(AWS_PROFILE) --tail
