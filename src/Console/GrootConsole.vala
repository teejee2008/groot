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
	public string basepath_bkup = "";
	public bool verbose = false;

	public bool share_internet = true;
	public bool share_display = true;

	public LinuxDistro distro = null;

	private string resolv_conf_bkup = "";

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

		string fmt = "  %-20s %s\n";

		//string fmt2 = "--- %s -----------------------------------\n\n"; //▰▰▰ ◈
		
		string msg = "\n" + AppName + " v" + AppVersion + " by %s (%s)".printf(AppAuthor, AppAuthorEmail) + "\n\n";

		msg += _("Usage") + ": groot [command] [basepath] [options]\n\n";

		msg += "%s:\n".printf(_("Commands"));
		msg += fmt.printf("--chroot", _("Change root to basepath (default if no command specified)"));
		msg += fmt.printf("--chroot-fstab", _("Read fstab file from basepath, mount devices under /tmp, and change root"));
		msg += fmt.printf("--list-devices", _("List current devices"));
		msg += fmt.printf("--sysinfo", _("Show current system information"));
		msg += "\n";
		
		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("--no-display", _("Do not share display (default: sharing enabled)"));
		msg += fmt.printf("--no-internet", _("Do not share internet connection (default: sharing enabled)"));
		msg += fmt.printf("--verbose, -v", _("Show executed commands"));
		msg += fmt.printf("--debug", _("Show debug messages"));
		msg += "\n";

		return msg;
	}

	public bool parse_arguments(string[] args) {

		string command = "chroot";
		
		// parse options and commands -------------------------------
		
		for (int k = 1; k < args.length; k++) {// Oth arg is app path

			switch (args[k].down()) {

			case "--chroot":
				command = "chroot";
				break;

			case "--chroot-fstab":
				command = "chroot-fstab";
				break;

			case "--fix-boot":
				command = "fix-boot";
				break;

			case "--list-devices":
				command = "list-devices";
				break;

			case "--sysinfo":
				command = "sysinfo";
				break;
				
			case "--basepath":
				k += 1;
				basepath = args[k];
				break;

			case "--debug":
				LOG_DEBUG = true;
				break;

			case "-v":
			case "--verbose":
				verbose = true;
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
				if (args[k].has_prefix("/")){
					if (file_exists(args[k])){
						basepath = args[k];
					}
					else {
						log_error("%s: %s".printf(_("Path not found"), args[k]));
						return false;
					}
				}
				else {
					// unknown option. show help and exit
					log_error(_("Unknown option") + ": %s".printf(args[k]));
					log_error(_("Run 'groot --help' for available commands and options"));
					return false;
				}
				break;
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
			
		case "chroot":
			return chroot();

		case "chroot-fstab":
			return chroot_fstab();

		case "fix-boot":
			return fix_boot();

		case "sysinfo":
			return sysinfo();

		case "list-devices":
			return list_devices();
		}

		return true;
	}

	// chroot -------------------------------------------------------
	
	private bool chroot(){

		check_admin_access();
		
		bool status = true;

		prepare_for_chroot();

		start_session();

		// session has ended --------------------------------------
		
		cleanup_after_chroot();

		return status;
	}

	private bool chroot_fstab(){

		check_admin_access();
		
		bool status = true, ok;

		ok = mount_system_devices();
		if (!ok){ return false; }
	
		prepare_for_chroot();

		start_session();

		// session has ended --------------------------------------
		
		cleanup_after_chroot();

		unmount_system_devices();

		return status;
	}

	private bool mount_system_devices(){

		string fstab = path_combine(basepath, "/etc/fstab");
		if (!file_exists(fstab)){
			log_error("%s: %s".printf(_("File Not Found"), fstab));
			log_error("%s".printf(_("Failed to mount system using fstab file")));
			log_error("%s".printf(_("Use 'groot --chroot' to change root normally")));
			return false;
		}

		var mgr = new MountEntryManager(false, basepath);
		mgr.read_mount_entries();

		var devices = Device.get_block_devices();

		basepath_bkup = basepath;
		basepath = "/tmp/%s".printf(timestamp_for_path());
		dir_create(basepath);

		foreach(var syspath in new string[] { "/", "/home", "/boot", "/boot/efi" }){

			var entry = mgr.get_entry_by_path(syspath); // check if entry exists

			if (entry != null){

				var dev = entry.get_device(devices);

				var mpath = path_combine(basepath, syspath);
				
				if (dev != null){

					string cmd = "mount";
					cmd += " -t %s".printf(entry.fs_type);
					cmd += " -o %s".printf(entry.options);
					cmd += " %s".printf(dev.device);
					cmd += " '%s'".printf(escape_single_quote(mpath));

					if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd); }

					Posix.system(cmd);
				}
			}
		}

		string cmd = "cd '%s'".printf(escape_single_quote(basepath));
		log_msg("\n$ " + cmd);
		Posix.system(cmd);

		return true;
	}

	private bool unmount_system_devices(){

		if (basepath.length == 0){ return false; }

		var mgr = new MountEntryManager(false, basepath);
		mgr.read_mount_entries();
		
		foreach(var syspath in new string[] { "/boot/efi", "/boot", "/home", "/" }){

			var entry = mgr.get_entry_by_path(syspath); // check if entry exists

			if (entry != null){
				
				var mpath = path_combine(basepath, syspath);
				
				string cmd = "umount";
				cmd += " '%s'".printf(escape_single_quote(mpath));
				
				if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd); }
				
				Posix.system(cmd);
			}
		}

		file_delete(basepath); // delete if empty

		basepath = basepath_bkup;

		string cmd = "cd '%s'".printf(escape_single_quote(basepath));

		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd); }
		
		Posix.system(cmd);
		
		return false;
	}

	private bool prepare_for_chroot(){

		check_dirs();

		mount_dirs();

		resolv_conf_bkup = "";
		if (share_internet){
			resolv_conf_bkup = copy_resolv_conf();
		}

		if (share_display){
			
			string cmd = "xhost +local:";

			if (!verbose && !LOG_DEBUG){
				cmd += " > /dev/null";
			}
			
			if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd); }
			Posix.system(cmd);
		}

		if (share_display){	
			run_chroot_commands("export DISPLAY=$DISPLAY");
		}

		return true;
	}

	private bool cleanup_after_chroot(){

		Posix.system("sync");

		if (share_internet){
			restore_resolv_conf();
		}

		unmount_dirs();

		return true;
	}
	
	private void check_dirs(){
	
		if (verbose || LOG_DEBUG){
			log_msg("\n%s=%s".printf(_("basepath"), basepath));
		}

		foreach(string name in new string[]{ "dev", "proc", "run", "sys" }){
			
			string path = path_combine(basepath, name);
			
			if (!dir_exists(path)){
				
				log_error("%s: %s".printf(_("Directory not found"), path));
				log_error(_("Path for chroot must have system directories: /dev, /proc, /run, /sys"));
				exit(1);
			}
		}
	}

	private void mount_dirs(){

		string cmd = "";

		cmd = "mount proc   '%s/proc'    -t proc     -o nosuid,noexec,nodev".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "mount sys    '%s/sys'     -t sysfs    -o nosuid,noexec,nodev,ro".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "mount udev   '%s/dev'     -t devtmpfs -o mode=0755,nosuid".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "mount devpts '%s/dev/pts' -t devpts   -o mode=0620,gid=5,nosuid,noexec".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "mount shm    '%s/dev/shm' -t tmpfs    -o mode=1777,nosuid,nodev".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "mount run    '%s/run'     -t tmpfs    -o nosuid,nodev,mode=0755".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "mount tmp    '%s/tmp'     -t tmpfs    -o mode=1777,strictatime,nodev,nosuid".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);
	}

	private void unmount_dirs(){

		string cmd = "";
		
		cmd = "umount --lazy --force --recursive '%s/dev'".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "umount --lazy --force --recursive '%s/run'".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "umount --lazy --force --recursive '%s/sys'".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "umount --lazy --force --recursive '%s/proc'".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);

		cmd = "umount --lazy --force --recursive '%s/tmp'".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd);
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

				if (verbose || LOG_DEBUG){
					
					string msg = "[%s] '%s' > '%s'".printf(
						_("moved"),
						escape_single_quote(conf_chroot.replace(basepath, "$basepath")),
						escape_single_quote(conf_chroot_bkup.replace(basepath, "$basepath")));
						
					log_msg("\n" + msg);
				}
			}

			file_copy(conf, conf_chroot, true);

			if (verbose || LOG_DEBUG){
					
				string msg = "[%s] '%s' > '%s'".printf(
					_("copied"),
					escape_single_quote(conf.replace(basepath, "$basepath")),
					escape_single_quote(conf_chroot.replace(basepath, "$basepath")));
					
				log_msg("\n" + msg);
			}
		}

		return conf_chroot_bkup;
	}

	private void restore_resolv_conf(){

		if (!share_internet){ return; }

		string conf = "/etc/resolv.conf";
		string conf_chroot = path_combine(basepath, conf);
		string conf_chroot_bkup = resolv_conf_bkup;
		
		// restore resolv.conf ------------------------------------

		if (file_exists(conf_chroot_bkup)){
			
			if (file_exists(conf_chroot)){
				
				file_delete(conf_chroot);

				if (verbose || LOG_DEBUG){
					
					string msg = "[%s] '%s'".printf(
						_("removed"),
						escape_single_quote(conf_chroot.replace(basepath, "$basepath")));
						
					log_msg("\n" + msg);
				}
			}

			file_move(conf_chroot_bkup, conf_chroot, false);

			if (verbose || LOG_DEBUG){
					
				string msg = "[%s] '%s' > '%s'".printf(
					_("moved"),
					escape_single_quote(conf_chroot_bkup.replace(basepath, "$basepath")),
					escape_single_quote(conf_chroot.replace(basepath, "$basepath")));
					
				log_msg("\n" + msg);
			}
		}
	}

	private void start_session(){

		show_session_message();

		string cmd = "SHELL=/bin/bash unshare --fork --pid chroot '%s'".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd); // --pid
	}

	private void show_session_message(){

		log_msg("");
		log_msg(string.nfill(70,'='));
		log_msg(_("Entering chroot environment..."));
		log_msg(string.nfill(70,'='));

		if (share_internet){
			log_msg(_("Internet sharing is Enabled (you can connect to internet)"));
		}
		else{
			log_msg(_("Internet sharing is Disabled"));
		}

		if (share_display){
			log_msg(_("Display sharing is Enabled (you can run GUI apps)"));
		}
		else{
			log_msg(_("Display sharing is Disabled"));
		}
		
		log_msg(string.nfill(70,'-'));
		log_msg(_("Type 'exit' to quit the session cleanly"));
		log_msg(string.nfill(70,'-'));
		//log_msg("");
	}

	private void run_chroot_commands(string commands){
		
		Posix.system("SHELL=/bin/bash unshare --fork --pid chroot '%s' /bin/bash -c \"%s\"".printf(
			escape_single_quote(basepath), commands));
	}

	// list devices ------------------------------

	private bool list_devices(){

		bool status = true;

		Posix.system("lsblk --fs");

		return status;
	}

	private bool sysinfo(){

		bool status = true;

		distro.print_system_info();

		return status;
	}
	
	// fix boot -----------------------------------------------------

	private bool fix_boot(){

		bool status = true;

		prepare_for_chroot();

		mount_system_devices();
		
		//start_session();

		// session has ended -------------
		
		cleanup_after_chroot();

		unmount_system_devices();

		return status;
	}

}
