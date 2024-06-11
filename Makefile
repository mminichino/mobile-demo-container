export CONTAINER := "mobiledemo"
export PROJECT_NAME := $$(basename $$(pwd))
export PROJECT_VERSION := $(shell cat VERSION)

.PHONY: script build push

commit:
	git commit -am "Version $(shell cat VERSION)"
	git push
patch:
	bumpversion --allow-dirty patch
minor:
	bumpversion --allow-dirty minor
major:
	bumpversion --allow-dirty major
push:
	docker image prune -f
	docker volume prune -f
	docker buildx prune -f
	docker system prune -a -f
	docker buildx build --platform linux/amd64,linux/arm64 \
	--no-cache \
	-t mminichino/$(CONTAINER):latest \
	-t mminichino/$(CONTAINER):$(PROJECT_VERSION) \
	-f Dockerfile . \
	--push
script:
	gh release create -R "mminichino/$(PROJECT_NAME)" \
	-t "Management Utility Release" \
	-n "Auto Generated Run Utility" \
	$(PROJECT_VERSION) rundemo.sh
build:
	docker image prune -f
	docker volume prune -f
	docker system prune -a -f
	docker build --force-rm=true --no-cache -t $(CONTAINER) -f Dockerfile .
