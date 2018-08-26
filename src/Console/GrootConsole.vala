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
public const string AppVersion = "18.1";
public const string AppAuthor = "Tony George";
public const string AppAuthorEmail = "teejeetech@gmail.com";

const string GETTEXT_PACKAGE = "";
const string LOCALE_DIR = "/usr/share/locale";

extern void exit(int exit_code);

public class GrootConsole : GLib.Object {

	public string basepath = "";
	public string basepath_bkup = "";
	public bool verbose = false;
	public bool mount_fstab = false;
	public bool fix_boot = false;
	public bool install_updates = false;
	
	public bool share_internet = true;
	public bool share_display = true;

	public LinuxDistro distro = null;

	private string resolv_conf_bkup = "";

	public static int main (string[] args) {
		
		set_locale();

		LOG_TIMESTAMP = false;

		//LOG_DEBUG = true;
		
		init_tmp(AppShortName);

		check_dependencies();

		Device.init();

		//Device.test_all();

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
		msg += fmt.printf("    --chroot", _("Chroot to [basepath] and open shell session (default)"));
		msg += fmt.printf("-f, --fixboot", _("Chroot to [basepath] and fix boot issues"));
		msg += fmt.printf("", _("(Rebuilds initramfs and updates GRUB menu)"));
		msg += fmt.printf("-s, --sysinfo", _("Show host system information"));
		msg += fmt.printf("-i, --guestinfo", _("Show guest system information"));
		msg += fmt.printf("-d, --list-devices", _("List current devices"));
		msg += "\n";
		
		msg += "%s:\n".printf(_("Options"));
		msg += fmt.printf("-m, --fstab", _("Mount devices from fstab and cryptab"));
		msg += fmt.printf("    --no-display", _("Do not share display (default: enabled)"));
		msg += fmt.printf("    --no-internet", _("Do not share internet connection (default: enabled)"));
		msg += fmt.printf("-v, --verbose", _("Show commands and extra messages"));
		msg += fmt.printf("    --debug", _("Show debug messages"));
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

			case "-m":
			case "--fstab":
			case "--chroot-fstab": // deprecated alias
				command = "chroot";
				mount_fstab = true;
				break;

			case "-f":
			case "--fixboot":
				command = "chroot";
				mount_fstab = true;
				fix_boot = true;
				break;

			case "-u":
			case "--update":
			case "--install-updates":
				command = "chroot";
				mount_fstab = true;
				install_updates = true;
				break;

			case "-d":
			case "--list-devices":
				command = "list-devices";
				break;

			case "-s":
			case "--sysinfo":
			case "--sys-info":
			case "--host-info":
				command = "sysinfo";
				break;

			case "-i":
			case "--guestinfo":
			case "--guest-info":
				command = "sysinfo-guest";
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

			case "-h":
			case "--help":
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

		case "sysinfo":
			return sysinfo();

		case "sysinfo-guest":
			return sysinfo_guest();

		case "list-devices":
			return list_devices();
		}

		return true;
	}

	// chroot -------------------------------------------------------
	
	private bool chroot(){

		check_dirs();

		check_admin_access();

		if (verbose || LOG_DEBUG){
			log_msg("\n%s=%s".printf(_("basepath"), basepath));
		}
		
		bool status = true, ok;

		if (mount_fstab){
			ok = mount_system_devices();
			if (!ok){ return false; }
		}

		prepare_for_chroot();

		if (fix_boot){
			fix_grub();
		}
		else if (install_updates){
			install_package_updates();
		}
		else {
			start_session();
		}

		// session has ended --------------------------------------
		
		cleanup_after_chroot();

		if (mount_fstab){
			unmount_system_devices();
		}

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

		if (verbose || LOG_DEBUG){
			log_msg("\n%s=%s".printf(_("basepath"), basepath));
		}

		if (verbose || LOG_DEBUG){
			log_msg("");
			log_msg(string.nfill(70,'-'));
			log_msg(_("Mounting devices from fstab and crypttab"));
			log_msg(string.nfill(70,'-'));
		}

		foreach(var entry in mgr.crypttab){

			var dev = Device.find_device_in_list(devices, entry.device);

			if (dev == null){
				if (!entry.options.contains("nofail")){
					log_error("%s: %s".printf(_("Could not find device referenced in crypttab file"), entry.device));
					return false;
				}
				else{
					continue;
				}
			}

			if (dev.is_encrypted_partition){

				if (!dev.is_unlocked){

					var cmd = "cryptsetup luksOpen '%s' '%s'".printf(dev.device, entry.name);
					if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd); }
					Posix.system(cmd);
						
					dev.query_changes();
					if (!dev.is_unlocked) { return false; }
				}
				else{

					if (dev.children[0].mapped_name != entry.name){
						// create device alias
						string cmd = "ln -s '%s' '/dev/mapper/%s'".printf(dev.children[0].device, entry.name);
						if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd); }
						Posix.system(cmd);
					}
				}
			}
		}

		devices = Device.get_block_devices();

		foreach(var entry in mgr.fstab){

			if (!entry.device.down().has_prefix("/") && !entry.device.down().has_prefix("uuid=")){ continue; }
			
			if (!entry.mount_point.has_prefix("/")){ continue; }

			var dev = Device.find_device_in_list(devices, entry.device);

			if (dev == null){
				if (!entry.options.contains("nofail")){
					log_error("%s: %s".printf(_("Could not find device referenced in fstab file"), entry.device));
					return false;
				}
				else{
					continue;
				}
			}

			var mpath = path_combine(basepath, entry.mount_point);

			if (!file_exists(mpath)){
				dir_create(mpath);
			}

			if (!file_exists(mpath)){
				log_error("%s: %s".printf(_("Path not found"), mpath));
				return false;
			}
			
			string cmd = "mount";
			cmd += " -t %s".printf(entry.fs_type);
			cmd += " -o %s".printf(entry.options);
			cmd += " %s".printf(dev.device);
			cmd += " '%s'".printf(escape_single_quote(mpath));

			if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }

			Posix.system(cmd);
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

		var devices = Device.get_block_devices();
		
		var list = mgr.fstab;
		list.sort((a,b)=>{ return strcmp(a.mount_point,b.mount_point) * -1; });

		if (verbose || LOG_DEBUG){
			log_msg("");
			log_msg(string.nfill(70,'-'));
			log_msg(_("Unmounting devices from fstab and crypttab"));
			log_msg(string.nfill(70,'-'));
		}

		// unmount in reverse order -----------------
		
		foreach(var entry in list){

			if (!entry.device.down().has_prefix("/") && !entry.device.down().has_prefix("uuid=")){ continue; }
			
			if (!entry.mount_point.has_prefix("/")){ continue; }

			var dev = Device.find_device_in_list(devices, entry.device);

			if (dev == null){
				if (!entry.options.contains("nofail")){
					log_error("%s: %s".printf(_("Could not find device referenced in fstab file"), entry.device));
					return false;
				}
				else{
					continue;
				}
			}

			var mpath = path_combine(basepath, entry.mount_point);
			
			string cmd = "umount --lazy --force";
			cmd += " '%s'".printf(escape_single_quote(mpath));

			if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }

			Posix.system(cmd);
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

			if (verbose || LOG_DEBUG){
				log_msg("");
				log_msg(string.nfill(70,'-'));
				log_msg(_("Enable display sharing"));
				log_msg(string.nfill(70,'-'));
			}
			
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

		if (verbose || LOG_DEBUG){
			log_msg("");
			log_msg(string.nfill(70,'-'));
			log_msg(_("Mounting system devices"));
			log_msg(string.nfill(70,'-'));
		}
		
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

		if (verbose || LOG_DEBUG){
			log_msg("");
			log_msg(string.nfill(70,'-'));
			log_msg(_("Unmounting system devices"));
			log_msg(string.nfill(70,'-'));
		}
		
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

		if (verbose || LOG_DEBUG){
			log_msg("");
			log_msg(string.nfill(70,'-'));
			log_msg(_("Copy resolv.conf"));
			log_msg(string.nfill(70,'-'));
		}

		string conf = "/etc/resolv.conf";
		string conf_chroot = path_combine(basepath, conf);
		string conf_chroot_bkup = path_combine(basepath, conf + ".groot-bkup");

		// fix for broken session ---------------------------------------

		if (file_exists(conf_chroot_bkup)){

			// restore the backup -------------------------
			
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

		if (verbose || LOG_DEBUG){
			log_msg("");
			log_msg(string.nfill(70,'-'));
			log_msg(_("Restore resolv.conf"));
			log_msg(string.nfill(70,'-'));
		}

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

		string cmd = "SHELL=/bin/bash unshare --fork --pid chroot '%s' /usr/bin/env -i HOME=/root USER=root /bin/bash -l".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd); // --pid
	}

	private bool fix_grub(){

		bool ok = write_fixboot_script();

		if (!ok){ return false; }

		string cmd = "SHELL=/bin/bash unshare --fork --pid chroot '%s' /usr/bin/env -i HOME=/root USER=root /bin/bash -c '/tmp/fixboot'".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd); // --pid

		return true;
	}

	private bool write_fixboot_script(){

		string sh_file = path_combine(basepath, "tmp/fixboot");

		file_delete(sh_file);
		
		string sh = "#!/bin/bash\n";
		string cmd = "";
		
		var dist = new LinuxDistro.from_path(basepath);

		log_msg(string.nfill(70,'-'));
		
		dist.print_system_info();

		sh += "echo '%s'\n".printf(string.nfill(70,'-'));

		// update initramfs -----------------------

		cmd = "";
		
		switch (dist.dist_type){
		case "debian":
			
			cmd = "update-initramfs -u -k all \n";
			break;
			
		case "fedora":

			cmd = "dracut -f -v \n";
			break;
			
		case "arch":

			cmd = "mkinitcpio -p /etc/mkinitcpio.d/*.preset \n";
			break;
			
		default:
			break;
		}

		sh += "echo '%s'\n".printf(escape_single_quote(cmd));
		sh += cmd;
		sh += "echo '%s'\n".printf(string.nfill(70,'-'));

		// update grub menu -------------------------------------

		cmd = "";
		
		switch (dist.dist_type){
		case "debian":

			cmd = "update-grub \n";
			break;
			
		case "fedora":
		case "arch":

			string cmd_name = "";

			if (cmd_exists_in_path(basepath, "grub-mkconfig")){
				cmd_name = "grub-mkconfig";
			}
			else if (cmd_exists_in_path(basepath, "grub2-mkconfig")){
				cmd_name = "grub2-mkconfig";
			}
			
			string grub_conf_name = "/boot/grub/grub.cfg";
			string grub_conf_path = path_combine(basepath, grub_conf_name);
			
			if (!file_exists(grub_conf_path)){
				grub_conf_name = "/boot/grub2/grub.cfg";
				grub_conf_path = path_combine(basepath, grub_conf_name);
			}
			
			if (!file_exists(grub_conf_path)){
				log_error(_("Failed to find GRUB config file. GRUB menu will not be updated."));
			}
			
			if ((cmd_name.length > 0) && file_exists(grub_conf_path)){
				cmd = "%s -o %s \n".printf(cmd_name, grub_conf_name);
			}
			
			break;
			
		default:
			break;
		}

		sh += "echo '%s'\n".printf(escape_single_quote(cmd));
		sh += cmd;
		//sh += "echo '%s'\n".printf(string.nfill(70,'-'));
		
		file_write(sh_file, sh);

		chmod(sh_file, "u+x");

		return file_exists(sh_file);
	}

	private bool install_package_updates(){

		bool ok = write_update_script();

		if (!ok){ return false; }

		string cmd = "SHELL=/bin/bash unshare --fork --pid chroot '%s' /usr/bin/env -i HOME=/root USER=root /bin/bash -c '/tmp/install-updates'".printf(escape_single_quote(basepath));
		if (verbose || LOG_DEBUG){ log_msg("\n$ " + cmd.replace(basepath, "$basepath")); }
		Posix.system(cmd); // --pid

		return true;
	}

	private bool write_update_script(){

		string sh_file = path_combine(basepath, "tmp/install-updates");

		file_delete(sh_file);
		
		string sh = "#!/bin/bash\n";
		string cmd = "";
		
		var dist = new LinuxDistro.from_path(basepath);

		log_msg(string.nfill(70,'-'));
		
		dist.print_system_info();

		sh += "echo '%s'\n".printf(string.nfill(70,'-'));
		
		cmd = "";
		
		switch (dist.dist_type){
		case "debian":
			
			cmd  = "%s update \n".printf(dist.package_manager);
			cmd += "%s upgrade \n".printf(dist.package_manager);
			break;
			
		case "fedora":

			cmd  = "%s check-update \n".printf(dist.package_manager);
			cmd += "%s upgrade \n".printf(dist.package_manager);
			break;
			
		case "arch":

			cmd = "%s -Syyu \n".printf(dist.package_manager);
			break;
			
		default:
			break;
		}

		sh += "echo '%s'\n".printf(escape_single_quote(cmd));
		sh += cmd;
		//sh += "echo '%s'\n".printf(string.nfill(70,'-'));

		file_write(sh_file, sh);

		chmod(sh_file, "u+x");

		return file_exists(sh_file);
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

		//Posix.system("lsblk --fs");

		//var devices = Device.get_block_devices();
		Device.print_device_list();

		return status;
	}

	private bool sysinfo(){

		bool status = true;

		distro.print_system_info();

		return status;
	}

	private bool sysinfo_guest(){

		bool status = true;

		var dist = new LinuxDistro.from_path(basepath);
		dist.print_system_info();

		return status;
	}
}
