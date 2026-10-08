# Release workflow skeleton for user repositories (Node layer) — dual trigger:
#   1. manual workflow_dispatch with a tag input (recommended);
#   2. optional tag push (commented out below — uncomment to enable).
# Fill the placeholder job steps in before use; irreversible actions
# (publish, release) must always run last, after validation.
name: Release

on:
  workflow_dispatch:
    inputs:
      tag:
        description: 'Tag to release (e.g. v1.2.3)'
        required: true
        type: string
  # push:
  #   tags: ['v*']

permissions:
  contents: read

jobs:
  validate:
    name: Validate release preconditions
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Preconditions
        run: echo "TODO: tag is semver, matches package.json version, exceeds the latest CHANGELOG version, and [Unreleased] is non-empty"

  publish:
    name: Publish to npm
    needs: validate
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Publish
        run: echo "TODO: build, then publish (irreversible — runs only after validate)"

  promote:
    name: Promote changelog and create GitHub Release
    needs: publish
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Promote
        run: echo "TODO: promote [Unreleased] into the version section, then create the GitHub Release"
