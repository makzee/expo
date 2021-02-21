---
title: Creating your first build
---

In this guide, you'll learn how to build a ready-to-submit binary for the Apple App Store and Google Play Store using EAS Build. For a simple app, you should expect to have kicked off your builds for Android and iOS within a few minutes.

## Prerequisites

EAS Build is a brand new and rapidly evolving service. It can't do everything yet, so before you set out to create a build for your project we recommend consulting the [limitations](/build-reference/limitations.md) page and the other prequisites below.

<details><summary><h4>📦 A React Native iOS and/or Android project that you want to build.</h4></summary>
<p>

Don't have a project yet? No problem: it's quick and easy to create a "Hello world" app that you can use with this guide.

<div style={{marginTop: -10}} />

- Install Expo CLI by running `npm install -g expo-cli` (or `yarn global add expo-cli`).
- Run `expo init PROJECT_NAME` (let's assume `PROJECT_NAME` is `abcd`) and choose a bare workflow template (either `minimal` or `minimal (TypeScript)`).
- EAS Build also works well with projects created by `npx react-native`, `create-react-native-app`, `ignite-cli`, and other project bootstrapping tools.

<center><img src="/static/images/eas-build/walkthrough/01-init.png" /></center>

</p>
</details>

> Support for managed workflow projects is rapidly improving, but not yet ready for production, so we recommend using it with bare React Native projects for best results right now.

<details><summary><h4>💡 An Expo account with an EAS Priority Plan subscription.</h4></summary>
<p>

- You can sign up for an Expo account at [https://expo.io/signup](https://expo.io/signup).
- Learn more about the EAS Priority Plan and sign up for a free month at [https://expo.io/pricing](https://expo.io/pricing).

</p>
</details>

> While EAS Build is in preview, it is available only to EAS Priority Plan subscribers. Once it graduates from preview it will become more broadly available. The first month is free, and you can cancel any time.

<details><summary><h4>🍎 If you want to build for iOS: Apple Developer Program membership.</h4></summary>
<p>

- If you are going to use EAS Build to create release builds for the Apple App Store, this requires access to an account with a \$99 USD [Apple Developer Program](https://developer.apple.com/programs) membership.

</p>
</details>

<!-- <details><summary><h4>🤖 If you want to build for the Play Store: Google Play Developer membership.</h4></summary>
<p>

- If you are going to use EAS Build to create release builds for the Google Play Store, this requries access to an account with a one-time $25 USD.

</p>
</details>

> There are other ways to distribute Android applications than Google Play, such as sharing an `apk` file directly with the user, and so this is not strictly required to use EAS Build for Android apps. -->

## 1. Install the latest EAS CLI

Install EAS CLI by running `npm install -g eas-cli` (or `yarn global add eas-cli`). It will notify you when a new version is available (we encourage you to always stay up to date with the latest version).

## 2. Log in to your Expo account

If you are already signed in through Expo CLI, you don't need to do anything. Otherwise, log in with `eas login`. You can check whether you're logged in by running `eas whoami`.

## 3. Configure the project

Run `eas build:configure` to configure your iOS and Android projects to run on EAS Build. If you'd like to learn more about what happens behind the scenes, you can read the [build configuration process reference](/build-reference/build-configuration.md).

Additional configuration may be required for some scenarios:

- Does your app code depend on environment variables? [Add them to your build configuration](/build-reference/variables.md).
- Is your project inside of a monorepo? [Follow these instructions](/build-reference/how-tos.md#how-to-set-up-eas-build-with).
- Do you use private npm packages? [Add your npm token](/build-reference/how-tos.md#how-to-use-private-package-repositories).

## 4. Run a build

- Run `eas build --platform android` to build for Android.

- Run `eas build --platform ios` to build for iOS.

- Alternatively, you can run `eas build --platform all` to build for Android and iOS at the same time.

Before the build can start, we'll need to generate or provide app signing credentials. If you have no experience with this, don't worry &mdash; no knowledge is required, you will be guided through the process and EAS CLI will do the heavy lifting.

> If you have released your app to stores previously and have existing [app signing credentials](/distribution/app-signing.md) that you would like to use, [follow these instructions to configure them](/app-signing/existing-credentials.md).

#### Android app signing credentials

- If you have not yet generated a keystore for your app, you can let EAS CLI take care of that for you by selecting `Generate new keystore`, and then you're done. The keystore will be stored securely on EAS servers.
- If you have previously built your app in the managed workflow with `expo build:android` (using the same `slug`), then the same credentials will be used here.
- If you would rather manually generate your keystore, please see the [manual Android credentials guide](/app-signing/local-credentials.md#android-credentials) for more information.

#### iOS app signing credentials

- If you have not generated a provisioning profile and/or distribution certificate yet, you can let EAS CLI take care of that for you by signing into your Apple Developer Program account and following the prompts.
- If you have already built your app in the managed workflow with `expo build:ios` (using the same `slug`), then the same credentials will be used here.
- If you would rather manually generate your credentials, refer to the [manual iOS credentials guide](/app-signing/local-credentials.md#ios-credentials) for more information.

## 5. Wait for the build to complete

By default, the `eas build` command will wait for your build to complete. However, if you interrupt this command and monitor the progress of your builds by either visiting [the EAS Build dashboard](https://expo.io/builds?type=eas) or running the `eas build:show` command.

## 6. Next steps

### Distribute your app

- Ship your app! [Learn how to submit your app to app stores with EAS Submit](/submit/introduction.md).
- Want to distribute your apps to internal testers? [Learn about internal distribution](internal-distribution.md).
  <!-- - Add new build profiles, such as simulator builds or build specific for certain release environments. -->

### Get a deeper understanding

- If you want to learn more about how of Android and iOS build jobs are performed, check out our [Android build process](/build-reference/android-builds.md) and [iOS build process](/build-reference/ios-builds.md) pages.
- Learn about the hardware infrastructure that the builds are run on and the software environment that they execute in on the [build server infrastructure reference](/build-reference/infrastructure.md)
- Learn about [caching dependencies](/build-reference/caching.md), [environment variables](/build-reference/variables.md), and [limitations of EAS Build](/build-reference/limitations.md).
