descriptor_file := container.txt
git_repo_file := repo.txt
CONTAINER := $(shell cat ${descriptor_file})
GIT_REPO := $(shell cat ${git_repo_file})
major_rev_file=major-revision.txt
minor_rev_file=minor-revision.txt
build_rev_file=build-revision.txt
MAJOR_REV := $(shell cat ${major_rev_file})
MINOR_REV := $(shell cat ${minor_rev_file})
BUILD_REV := $(shell cat ${build_rev_file})

.PHONY: script build push

push:
	git pull
	@if ! test -f $(build_rev_file); then echo 0 > $(build_rev_file); fi
	@echo $$(($$(cat $(build_rev_file)) + 1)) > $(build_rev_file)
	@if ! test -f $(major_rev_file); then echo 1 > $(major_rev_file); fi
	@if ! test -f $(minor_rev_file); then echo 0 > $(minor_rev_file); fi
	$(eval MAJOR_REV := $(shell cat $(major_rev_file)))
	$(eval MINOR_REV := $(shell cat $(minor_rev_file)))
	$(eval BUILD_REV := $(shell cat $(build_rev_file)))
	docker buildx build --platform linux/amd64,linux/arm64 \
	--no-cache \
	-t mminichino/$(CONTAINER):latest \
	-t mminichino/$(CONTAINER):$(MAJOR_REV).$(MINOR_REV).$(BUILD_REV) \
	-f Dockerfile . \
	--push
	git add -A .
	git commit -m "Build version $(MAJOR_REV).$(MINOR_REV).$(BUILD_REV)"
	git push -u origin main
script:
	sed -e "s/CONTAINER_NAME/$(CONTAINER)/" rundemo.template > rundemo.sh
	gh release create -R $(GIT_REPO) \
	-t "Management Utility Release" \
	-n "Auto Generated Run Utility" \
	$(MAJOR_REV).$(MINOR_REV).$(BUILD_REV) rundemo.sh
build:
	docker build --force-rm=true --no-cache=true -t $(CONTAINER) -f Dockerfile .
