import * as React from 'react';

import {launchImageLibrary} from 'react-native-image-picker';
import { StyleSheet, View, Text, TouchableOpacity } from 'react-native';
import { upload } from 'react-native-uploadcare-uploader';

export default function App() {

  const [uuid, setUuid] = React.useState('Nothing yet!')

  const handleUpload = React.useCallback(() => {
    launchImageLibrary({
      mediaType: 'video'
    }).then(response => {
      const file = response.assets ? response.assets[0] : null
      if (file) {
        upload('45abe1dd3ff00425e6bd', file.uri!.replace('file://', ''), 'video/mp4').then(setUuid).catch(() => setUuid('error'))
      }
    })
  }, [])

  return (
    <View style={styles.container}>
      <TouchableOpacity onPress={handleUpload}><Text>{uuid}</Text></TouchableOpacity>
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
