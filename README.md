# ChatSharedDataManager

Shared data manager for chat app and extensions.

## Features

- JWT token management across app and extensions
- Contact data access with Realm integration
- API calls with proper authentication
- Multi-process MMKV support

## Installation

Add this to your Podfile:

```ruby
pod 'SharedDataManager', :git => 'https://github.com/qusaieilouti99/chat-shared-swift-module.git'
```

Then run:

```bash
pod install
```

## Usage

```swift
import ChatSharedDataManager

// Get JWT token
let token = SharedDataManager.shared.getJWTToken(hostAppBundleId: "com.yourapp.bundle")

// Get contact by username
let contact = SharedDataManager.shared.getContact(byUsername: "username", hostAppBundleId: "com.yourapp.bundle")

// Send message acknowledgement
SharedDataManager.shared.sendMessageAcknowledgement(
    messageId: "messageId",
    userId: "userId", 
    hostAppBundleId: "com.yourapp.bundle"
)
```

## Requirements

- iOS 16.0+
- Swift 5.0+
- MMKV
- RealmSwift

## License

ChatSharedDataManager is available under the MIT license. See the LICENSE file for more info.