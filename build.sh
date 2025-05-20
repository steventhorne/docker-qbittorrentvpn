#!/usr/bin/env bash
set -a && source build.env && set +a
docker build \
  --build-arg BOOST_VERSION_DOT \
  --build-arg BOOST_VERSION \
  -t steventhorne/qbittorrentvpn .
