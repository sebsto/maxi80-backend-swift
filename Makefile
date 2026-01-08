format:
	swift format -i -r Package.swift Sources
build:
	swift package archive --allow-network-connections docker --disable-docker-image-update --target Maxi80Lambda 	