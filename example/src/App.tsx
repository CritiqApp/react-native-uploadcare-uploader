import * as React from 'react';

import {launchImageLibrary} from 'react-native-image-picker';
import { StyleSheet, View, Text, TouchableOpacity } from 'react-native';
import Uploader from 'react-native-uploadcare-uploader';

export default function App() {

  const [uuid, setUuid] = React.useState('Nothing yet!')
  const [progress, setProgress] = React.useState(0)

  const handleUpload = React.useCallback(() => {
    launchImageLibrary({
      mediaType: 'video'
    }).then(response => {
      const file = response.assets ? response.assets[0] : null
      if (file) {
        Uploader.upload("some-id",
          {
            uri: file.uri!.replace('file://', ''),
            mimeType: 'video/mp4',
          }, {
            onProgress: (current, total) => setProgress(current / total),
            onUUIDCreated: (uuid) => console.log('uuid'),
            metadata: { 'test': "THIS IS A TEST"}
          }
        ).then(uuid => {
          console.log('DONE')
          setUuid(uuid)
        }).catch(() => setUuid('error'))
      }
    })
  }, [])

  return (
    <View style={styles.container}>
      <TouchableOpacity onPress={handleUpload}><Text>{uuid}</Text></TouchableOpacity>
      <Text>{Math.round(progress * 100) + '%'}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  box: {
    width: 60,
    height: 60,
    marginVertical: 20,
  },
});
