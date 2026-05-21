.PHONY: push github push_github

push: push_github

github:
	@true

push_github:
	./push_source.sh

%:
	$(MAKE) -C sim $@
