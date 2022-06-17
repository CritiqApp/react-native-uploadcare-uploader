# react-native-uploadcare-uploader

A React-Native wrapper for Uploadcares Swift library

## Installation

```sh
npm install react-native-uploadcare-uploader
```
or
```sh
yarn react-native-uploadcare-uploader
```

# Dependencies

None

## Usage

```js
import Uploader from "react-native-uploadcare-uploader";

// ...

// Note - if filePath is prefixed with "file://"
// strip this with filePath.replace('file://', '')
const handleUpload = React.useCallback((filePath, mimeType) => {
    Uploader.upload("uploadcare public key", filePath, mimeType)
}, [])
```

# Background upload notes

1. Background uploads only apply to multipart uploading, any direct upload will either hang until the app is resumed or fail
2. If you are connected to an xcode debugger, the app is never suspended and thus the background upload appears to not work.

## How it works

This will automatically handle picking between multipart and direct uploads to Uploadcare. Any files less than 10MB will use direct uploads, anything larger multipart. Multipart uploads chunk the files into 5MB sections. Maybe in the future I can make this configurable.

## Contributing

I built this project to solve a very specific problem for my work, feel free to contribute if you'd like

# Credits
Some code from the [uploadcare-swift](https://github.com/uploadcare/uploadcare-swift) library was used to help with making requests to the Uploadcare API.

## License

MIT
