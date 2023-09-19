#!/usr/bin/env node

import { Command } from 'commander';
import migrator from './index';

const program = new Command();

program
  .name('migrate-to-localwp')
  .description('Quickly generate an import file for Local (by Flywheel).')
  .argument('<ssh-username>', 'The SSH user to use to connect to the remote server')
  .argument('<ssh-host>', 'The SSH host to use to connect to the remote server')
  .argument('<public-path>', 'The path to the public directory on the remote server')
  .option('-p, --password <password>', 'Directly specify the ssh password')
  .option('-v, --verbose', 'Enable verbose logging', false)
  .version('0.0.0')
  .action(async (sshUsername, sshHost, publicPath, options) => {
    await migrator(sshHost, sshUsername, options.password, publicPath);
  });

program.parse();
