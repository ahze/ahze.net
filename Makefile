HUGO = hugo

.PHONY: serve build clean

serve:
	$(HUGO) server -D --bind 0.0.0.0 --port 1313 --baseURL http://saturn:1313 --appendPort=false

build:
	$(HUGO)

clean:
	rm -rf public/
