sam local generate-event apigateway http-api-proxy > events/api.json
LOCAL_LAMBDA_SERVER_ENABLED=true LOG_LEVEL=debug swift run Maxi80Backend
curl -X POST -H "Content-Type: application/json" -d @./events/api.json http://127.0.0.1:7000/invoke
 
swift package --disable-sandbox archive
swift package --disable-sandbox deploy

curl -v  https://i24d9nloya.execute-api.us-east-1.amazonaws.com/

# TLS certificate 

