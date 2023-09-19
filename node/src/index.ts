import { Client, FileEntry, SFTPWrapper } from 'ssh2';
import fs from 'fs';
import path from 'path';
import os from 'os';

export default async function main(host: string, username: string, password: string, pathToPublic: string, port: number = 22) {
  const pathToWpConfig = pathToPublic + '/wp-config.php';

  const conn = new Client();
  conn.on('ready', () => {
    console.log('Client :: ready');



    // conn.exec('mysql -h localhost -u am_marlton -p548a7fb5ca25d98c -e"quit"', (err, stream) => {
    //   if (err) throw err;
    //   stream.on('close', (code: any, signal: any) => {
    //     console.log('Stream :: close :: code: ' + code + ', signal: ' + signal);
    //     conn.end();
    //   }).on('data', (data: any) => {
    //     console.log('STDOUT: ' + data);
    //   }).stderr.on('data', (data) => {
    //     console.log('STDERR: ' + data);
    //   });
    // });




    conn.sftp(async (err, sftp) => {
      if (err) throw err;

      // Assert that the wp-config.php file exists
      sftp.exists(pathToWpConfig, (exists: boolean) => {
        if (!exists) {
          console.log('File does not exist');
          conn.end();
          throw new Error(`Could not find wp-config.php at '${pathToWpConfig}'`);
        }
      });


      // sftp.readFile(pathToWpConfig, (err, data) => {
      //   if (err) throw err;
      //   // console.log('File contents: ' + data);
      //   // conn.end();
      //
      //   // Parse the database name, user, and password from the wp-config.php file
      //   const wpConfig = data.toString();
      //   const dbName = getWpConfigValue(wpConfig, 'DB_NAME');
      //   const dbUser = getWpConfigValue(wpConfig, 'DB_USER');
      //   const dbPassword = getWpConfigValue(wpConfig, 'DB_PASSWORD');
      //
      //
      //   // Assert that we can connect to the database
      //   conn.exec(`mysql -h localhost -u ${dbUser} -p${dbPassword} -e"quit"`, (err, stream) => {
      //     if (err) throw err;
      //
      //     stream.on('close', (code: number) => {
      //       // conn.end();
      //
      //       if (code !== 0) {
      //         throw new Error(`Could not connect to the database with the credentials in wp-config.php. (Code: ${code})`);
      //       }
      //     }).on('data', () => {}).stderr.on('data', () => {});
      //   });
      //
      // });


      // Create a temporary directory to download the files to
      const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'migrate-to-localwp-'));

      // Download the entire public directory to the temporary directory
      // await downloadRemoteDirectory(sftp, pathToPublic, tmpDir);

      console.log('Closing connection');
      conn.end();


      // sftp.readdir(pathToPublic, (err, list) => {
      //   if (err) throw err;
      //   // console.dir(list);
      //
      //   for (const file of list) {
      //     console.log(file.filename);
      //   }
      //
      //
      //   conn.end();
      // });



      // // Download the wp-config.php file to the temporary directory
      // sftp.fastGet(pathToPublic, tmpDir + '/', (err) => {
      //   if (err) throw err;
      //   console.log('wp-config.php downloaded to ' + tmpDir + '/wp-config.php');
      //   conn.end();
      // });

      // let rs = sftp.createReadStream(sourcePath)
      // let ws = sftp.createWriteStream(dstPath)
      // rs.pipe(ws)


    });
  }).connect({
    host: host,
    port: port,
    username: username,
    password: password
  });
}

function getWpConfigValue(wpConfigContents: string, field: 'DB_NAME' | 'DB_USER' | 'DB_PASSWORD'): string {
  const match = wpConfigContents.match(new RegExp(`define\\(\\s*'${field}'\\s*,\\s*'(.*)'\\s*\\);`));

  if (match === null) {
    throw new Error(`Could not find '${field}' in wp-config.php`);
  }

  return match[1];
}

async function downloadRemoteDirectory(sftp: SFTPWrapper, pathToRemoteDirectory: string, pathToLocalDirectory: string): Promise<void> {
  return await copyDirectoryToPath(sftp, pathToRemoteDirectory, pathToLocalDirectory);
}

 async function copyDirectoryToPath(sftp: SFTPWrapper, pathToRemoteDirectory: string, pathToLocalDirectory: string): Promise<void> {

  // return new Promise((resolve, reject) => {
  //   listDirectory(sftp, pathToRemoteDirectory).then((list) => {
  //     const promises: any[] = [];
  //
  //     list.forEach((file) => {
  //
  //       const pathToRemoteFile = path.join(pathToRemoteDirectory, file.filename);
  //       const pathToLocalFile = path.join(pathToLocalDirectory, file.filename);
  //
  //       // @ts-ignore
  //       const isDirectory = file.attrs.isDirectory();
  //
  //       if (isDirectory) {
  //         // Create the directory
  //         fs.mkdirSync(pathToLocalFile);
  //       }
  //
  //       promises.push(isDirectory ? copyDirectoryToPath(sftp, pathToRemoteFile, pathToLocalFile) : downloadFile(sftp, pathToRemoteFile, pathToLocalFile));
  //     });
  //
  //     Promise.all(promises).then(() => {
  //       resolve();
  //     });
  //   });
  // });


  const list = await listDirectory(sftp, pathToRemoteDirectory);

  for (const file of list) {
    const pathToRemoteFile = path.join(pathToRemoteDirectory, file.filename);
    const pathToLocalFile = path.join(pathToLocalDirectory, file.filename);

    const directories = [];
    const downloadPromises = [];
    // Create all the files in this directory before processing the next directory
    // @ts-ignore
    if (file.attrs.isDirectory()) {
      directories.push(file.filename);
    } else {
      // Download the file
      downloadPromises.push(downloadFile(sftp, pathToRemoteFile, pathToLocalFile));
    }

    await Promise.all(downloadPromises);

    for (const directory of directories) {
      // Create the directory
      fs.mkdirSync(path.join(pathToLocalDirectory, directory));

      await copyDirectoryToPath(sftp, path.join(pathToRemoteDirectory, directory), path.join(pathToLocalDirectory, directory));
    }

    // // Check if the file is a directory
    // // @ts-ignore
    // if (file.attrs.isDirectory()) {
    //   // Create the directory
    //   fs.mkdirSync(path.join(pathToLocalDirectory, file.filename));
    //
    //   // Copy the files in the directory
    //   await copyDirectoryToPath(sftp, path.join(pathToRemoteDirectory, file.filename), path.join(pathToLocalDirectory, file.filename));
    // } else {
    //   // Download the file
    //   await downloadFile(sftp, path.join(pathToRemoteDirectory, file.filename), path.join(pathToLocalDirectory, file.filename));
    //   console.log('File downloaded to ' + path.join(pathToLocalDirectory, file.filename));
    //   // sftp.fastGet(path.join(pathToRemoteDirectory, file.filename), path.join(pathToLocalDirectory, file.filename), (err) => {
    //   //   if (err) throw err;
    //   //   console.log('File downloaded to ' + path.join(pathToLocalDirectory, file.filename));
    //   // });
    // }
  }
}

function listDirectory(sftp: SFTPWrapper, pathToRemoteDirectory: string): Promise<FileEntry[]> {
  return new Promise((resolve, reject) => {
    sftp.readdir(pathToRemoteDirectory, (err, list) => {
      if (err) reject(err);
      resolve(list);
    });
  });
}

function downloadFile(sftp: SFTPWrapper, pathToRemoteFile: string, pathToLocalFile: string): Promise<void> {
  return new Promise((resolve, reject) => {
    sftp.fastGet(pathToRemoteFile, pathToLocalFile, (err) => {
      if (err) reject(err);
      console.log('File downloaded to ' + pathToLocalFile)
      resolve();
    });
  });
}
