/*
 * GrootConsole.vala
 *
 * Copyright 2012-2017 Tony George <teejeetech@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

using GLib;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;
using TeeJee.System;
using TeeJee.Misc;

public const string AppName = "Groot";
public const string AppShortName = "groot";
public const string AppVersion = "17.12";
public const string AppAuthor = "Tony George";
public const string AppAuthorEmail = "teejeetech@gmail.com";

const string GETTEXT_PACKAGE = "";
const string LOCALE_DIR = "/usr/share/locale";

extern void exit(int exit_code);

public class GrootConsole : GLib.Object {

	public string basepath = "";

	public bool share_internet = true;
	public bool share_display = true;
	
	public LinuxDistro distro = null;

	public static int main (string[] args) {
		
		set_locale();

		LOG_TIMESTAMP = false;

		init_tmp(AppShortName);

		check_dependencies();

		var console =  new GrootConsole();
		bool is_success = console.parse_arguments(args);
		return (is_success) ? 0 : 1;
	}

	private static void set_locale() {
		Intl.setlocale(GLib.LocaleCategory.MESSAGES, "groot");
		Intl.textdomain(GETTEXT_PACKAGE);
		Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "utf-8");
		Intl.bindtextdomain(GETTEXT_PACKAGE, LOCALE_DIR);
	}

	public static void check_dependencies(){

		string[] dependencies = {
			"mount", "umount", "xhost", "chroot", "unshare"
		};

		string missing = "";
		
		foreach(string cmd in dependencies){
			
			if (!cmd_exists(cmd)){
				
				if (missing.length > 0){
					missing = ", ";
				}
				missing += cmd;
			}
		}

		if (missing.length > 0){
			string msg ="%s: %s".printf(Messages.MISSING_COMMAND, missing);
			log_error(msg);
			log_error(_("Install required packages for missing commands"));
			exit(1);
		}
	}

	public void check_admin_access(){

		if (!user_is_admin()) {
			log_msg(_("groot needs admin access to change root"));
			log_msg(_("Run groot as admin (using 'sudo' or 'pkexec')"));
			exit(0);
		}
	}
	
	public GrootConsole(){

		distro = new LinuxDistro();

		basepath = Environment.get_current_dir();
	}

	public void print_backup_path(){
		
		log_msg("Backup path: %s".printf(basepath));
		log_msg(string.nfill(70,'-'));
	}

	public string help_message() {

		string fmt = "  %-30s %s\n";

		//string fmt2 = "--- %s -----------------------------------\n\n"; //▰▰▰ ◈
		
		string msg = "\n" + AppName + " v" + AppVersion + " by %s (%s)".printf(AppAuthor, AppAuthorEmail) + "\n\n";

		msg += _("Usage") + ": groot [basepath] [options]\n\n";

		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("--no-display", _("Do not share display (default: enabled)"));
		msg += fmt.printf("--no-internet", _("Do not share internet connection (default: enabled)"));
		msg += fmt.printf("--debug", _("Show debug messages"));
		msg += "\n";

		return msg;
	}

	public bool parse_arguments(string[] args) {

		string command = "--chroot";
		
		// parse options and commands -------------------------------
		
		for (int k = 1; k < args.length; k++) {// Oth arg is app path

			switch (args[k].down()) {
			case "--basepath":
				k += 1;
				basepath = args[k] + (args[k].has_suffix("/") ? "" : "/");
				break;

			case "--debug":
				LOG_DEBUG = true;
				break;
				
			case "--no-display":
				share_display = false;
				break;

			case "--no-internet":
				share_internet = false;
				break;
				
			case "--help":
			case "--h":
			case "-h":
				log_msg(help_message());
				return true;

			default:
				// unknown option. show help and exit
				log_error(_("Unknown option") + ": %s".printf(args[k]));
				log_error(_("Run 'groot --help' for available commands and options"));
				return false;
			}
		}

		if (command.length == 0){
			// no command specified
			log_error(_("No command specified!"));
			log_error(_("Run 'groot --help' for available commands and options"));
			return false;
		}

		// process command ----------------------------------
		
		switch (command) {
			
		case "--chroot":
			return chroot();
		}

		return true;
	}

	public bool chroot(){

		bool status = true;

		check_admin_access();

		check_dirs();

		mount_dirs();

		string bkup_file = "";

		if (share_internet){
			bkup_file = copy_resolv_conf();
		}

		if (share_display){
			Posix.system("xhost +local:");
		}

		show_session_message();

		if (share_display){	
			Posix.system("chroot '%s' /bin/bash -c \"export DISPLAY=$DISPLAY\"".printf(escape_single_quote(basepath)));
		}

		start_session();

		// session has ended --------------------------------------
		
		end_session();

		if (share_internet){
			restore_resolv_conf(bkup_file);
		}

		unmount_dirs();

		return status;
	}

	private void check_dirs(){

		foreach(string name in new string[]{ "dev", "proc", "run", "sys" }){
			
			string path = path_combine(basepath, name);
			
			if (!dir_exists(path)){
				
				log_error("%s: %s".printf(_("Directory not found"), path));
				log_error("Path for chroot must have system directories: /dev, /proc, /run, /sys");
				exit(1);
			}
		}
	}

	private void mount_dirs(){

		Posix.system("mount proc   '%s/proc'    -t proc     -o nosuid,noexec,nodev".printf(escape_single_quote(basepath)));
		Posix.system("mount sys    '%s/sys'     -t sysfs    -o nosuid,noexec,nodev,ro".printf(escape_single_quote(basepath)));
		Posix.system("mount udev   '%s/dev'     -t devtmpfs -o mode=0755,nosuid".printf(escape_single_quote(basepath)));
		Posix.system("mount devpts '%s/dev/pts' -t devpts   -o mode=0620,gid=5,nosuid,noexec".printf(escape_single_quote(basepath)));
		Posix.system("mount shm    '%s/dev/shm' -t tmpfs    -o mode=1777,nosuid,nodev".printf(escape_single_quote(basepath)));
		Posix.system("mount run    '%s/run'     -t tmpfs    -o nosuid,nodev,mode=0755".printf(escape_single_quote(basepath)));
		Posix.system("mount tmp    '%s/tmp'     -t tmpfs    -o mode=1777,strictatime,nodev,nosuid".printf(escape_single_quote(basepath)));
	}

	private void unmount_dirs(){

		Posix.system("umount --lazy --force --recursive '%s/dev'".printf(escape_single_quote(basepath)));
		Posix.system("umount --lazy --force --recursive '%s/run'".printf(escape_single_quote(basepath)));
		Posix.system("umount --lazy --force --recursive '%s/sys'".printf(escape_single_quote(basepath)));
		Posix.system("umount --lazy --force --recursive '%s/proc'".printf(escape_single_quote(basepath)));
		Posix.system("umount --lazy --force --recursive '%s/tmp'".printf(escape_single_quote(basepath)));
	}

	private string copy_resolv_conf(){

		if (!share_internet){ return ""; }

		string ts = timestamp_for_path();

		string conf = "/etc/resolv.conf";
		string conf_chroot = path_combine(basepath, conf);
		string conf_chroot_bkup = path_combine(basepath, conf + ".bkup-%s".printf(ts));

		// copy resolv.conf -----------------------------------------

		if (file_exists(conf)){

			if (file_exists(conf_chroot)){

				file_move(conf_chroot, conf_chroot_bkup, false);
			}

			file_copy(conf, conf_chroot, true);
		}

		return conf_chroot_bkup;
	}

	private void restore_resolv_conf(string conf_chroot_bkup){

		if (!share_internet){ return; }

		string conf = "/etc/resolv.conf";
		string conf_chroot = path_combine(basepath, conf);

		// restore resolv.conf ------------------------------------

		if (file_exists(conf_chroot_bkup)){
			
			if (file_exists(conf_chroot)){
				
				file_delete(conf_chroot);
			}

			file_move(conf_chroot_bkup, conf_chroot, false);
		}
	}

	private void start_session(){

		Posix.system("SHELL=/bin/bash unshare --fork --pid chroot '%s'".printf(escape_single_quote(basepath)));
	}

	private void end_session(){

		Posix.system("sync");
	}

	private void show_session_message(){

		log_msg(string.nfill(70,'='));
		log_msg("Entering chroot environment... ");
		log_msg(string.nfill(70,'='));

		if (share_internet){
			log_msg("Internet Sharing: Enabled (you can connect to internet)");
		}
		else{
			log_msg("Internet Sharing: Disabled");
		}

		if (share_display){
			log_msg("Display  Sharing: Enabled (you can run GUI apps)");
		}
		else{
			log_msg("Display  Sharing: Disabled");
		}
		
		log_msg(string.nfill(70,'-'));
		log_msg("Type 'exit' to quit the session cleanly");
		log_msg(string.nfill(70,'-'));
		log_msg("");
	}
}
