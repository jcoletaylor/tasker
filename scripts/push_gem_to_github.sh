#!/bin/bash
# bundle exec gem build
gem push --key github --host https://rubygems.pkg.github.com/jcoletaylor $1
