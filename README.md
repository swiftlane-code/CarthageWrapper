# What is CarthageWrapper

This is a wrapper around [Carthage CLI](https://github.com/Carthage/Carthage) that helps you to build specific versions of your dependencies only once and then reuse the built binaries.

Version of Xcode used to build binaries is taken into account.

CarthageWrapper also provides a way to download binary-only dependencies without using _Carthage CLI_ at all. Carthage itself is not that flexible when you need to download a binary-only dependency. Furthermore this is not possible at all if you have some specific kind of authentication on the backend side.

> Fat binaries are sliced into xcframeworks. This way you get meaningful build errors when one of your dependencies doesn't support target architecture or platform.

## Remote Storage

Built binaries are stored in form of zipped xcframeworks in a **remote storage**. 

> For now [GitLab Packages](https://docs.gitlab.com/ee/user/packages/package_registry/index.html) is the only supported **remote storage** (zips are uploaded as [Generic Packages](https://docs.gitlab.com/ee/user/packages/generic_packages/)). 

Projects which produce multiple xcframeworks are zipped into single .zip archive.

CarthageWrapper also caches zip archives with prebuilt binaries locally to prevent excessive downloads. This is extremely handful when you need to frequently switch between branches of your project which have different dependencies version.

## Versioning of binaries

Built dependencies are versioned in the following format:
```
<version of dependency>_<swift version>_<builder version>
```
Where:
* `<version of dependency>` - version or commit SHA of the dependency repo.
* `<swift version>` - version of swift tools which were used to build the dependency. This is parsed from `$ swift --version` output.
* `<builder version>` - version of logic used to resolve versions of built binaries. This is defined as `let wrapperVersion: String = "2"` in [BootstrapCommandRunner.swift](./Sources/CarthageWrapper/AppLevel/Commands/Bootstrap/BootstrapCommandRunner.swift).

##### Example:
Let's say this is your `Cartfile.resolved`:
```
github "MakeAWishFoundation/SwiftyMocky" "4.2.0"
```
Then CarthageWrapper will pack `SwiftyMocky.xcframework` into a zip file named `SwiftyMocky@4.2.0_swift-5.6.1_builder-2.zip`.

## Binary-only dependencies

All binary-only dependencies should be listed in `CartfileBinary.yml` and not in `Cartfile`.

Downloading of binary-only dependencies is done without any help of  _Carthage CLI_.

So that you have to list only the dependencies which you are willing to build from source in your `Cartfile` and `Cartfile.resolved`.

# How it works under the hood

1) Execute `$ carthage bootstrap --no-build`.
1) Parse `Cartfile.resolved` and `CartfileBinary.yml`
1) Try to download prebuilt binaries of required dependencies from (2):
	* prebuilt binaries are either downloaded from url
		specified in `CartfileBinary.yml` or from the **remote storage**.
1) If downloading of a prebuilt binary failed:
	1) Execute `$ carthage build ... --use-xcframeworks` to build it.
	1) Upload built binaries to the **remote storage**.
1) Slice fat binaries in `Carthage/Build/iOS` and create respective
xcframeworks in `Carthage/Build`.

Correct state of `Carhage/Build` folder is guaranteed by use of `*.smversion` files which are placed alongside the binaries. These files are used to track versions of dependencies which are currently ready-to-use.
