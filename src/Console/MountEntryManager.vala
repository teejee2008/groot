/*
 * MountEntryManager.vala
 *
 * Copyright 2017 Tony George <teejeetech@gmail.com>
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

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;
using TeeJee.Misc;

public class MountEntryManager : GLib.Object {

	public string basepath = "/";
	
	public Gee.ArrayList<FsTabEntry> fstab;
	public Gee.ArrayList<CryptTabEntry> crypttab;

	public bool dry_run = false;

	public MountEntryManager(bool _dry_run = false, string filesystem_root_path = "/"){

		dry_run = _dry_run;

		basepath = filesystem_root_path;
		
		fstab = new Gee.ArrayList<FsTabEntry>();
		crypttab = new Gee.ArrayList<CryptTabEntry>();
	}

	// read -----------------------------
	
	public void read_mount_entries(){

		read_fstab_file();

		read_crypttab_file();

		update_device_uuids();
	}

	public bool read_fstab_file(){

		string tab_file = "/etc/fstab";

		if (basepath.length > 1){
			tab_file = path_combine(basepath, tab_file);
		}

		if (!file_exists(tab_file)){
			log_error("%s: %s".printf(Messages.FILE_MISSING, tab_file));
			return false;
		}
		
		string txt = file_read(tab_file);
		
		foreach(string line in txt.split("\n")){
			
			parse_fstab_line(line);
		}

		return true;
	}

	public bool read_crypttab_file(){

		string tab_file = "/etc/crypttab";

		if (basepath.length > 1){
			tab_file = path_combine(basepath, tab_file);
		}

		if (!file_exists(tab_file)){
			log_error("%s: %s".printf(Messages.FILE_MISSING, tab_file));
			return false;
		}
		
		string txt = file_read(tab_file);
		
		foreach(string line in txt.split("\n")){

			parse_crypttab_line(line);
		}

		return true;
	}

	private void parse_fstab_line(string line){
		
		if ((line == null) || (line.length == 0)){ return; }

		if (line.strip().has_prefix("#")){ return; }
		
		FsTabEntry entry = null;

		//<device> <mount point> <type> <options> <dump> <pass>
		
		var match = regex_match("""([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)""", line);

		if (match != null){
			
			entry = new FsTabEntry();
			
			entry.device = match.fetch(1);
			entry.mount_point = match.fetch(2);
			entry.fs_type = match.fetch(3);
			entry.options = match.fetch(4);
			entry.dump = match.fetch(5);
			entry.pass = match.fetch(6);
			
			fstab.add(entry);
		}
	}

	private void parse_crypttab_line(string line){
		
		if ((line == null) || (line.length == 0)){ return; }

		if (line.strip().has_prefix("#")){ return; }
		
		CryptTabEntry entry = null;

		//<name> <device> <password> <options>
		
		var match = regex_match("""([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)""", line);

		if (match != null){
			
			entry = new CryptTabEntry();
			
			entry.name = match.fetch(1);
			entry.device = match.fetch(2);
			entry.password = match.fetch(3);
			entry.options = match.fetch(4);
			
			crypttab.add(entry);
		}
	}

	private void update_device_uuids(){
		
		var devices = Device.get_block_devices();
		
		foreach(var entry in fstab){

			if (!entry.device.up().contains("UUID=") && !entry.device.down().has_prefix("/dev/disk/")){

				var dev = Device.find_device_in_list(devices, entry.device);
				if ((dev != null) && (dev.uuid.length > 0)){
					entry.device = "UUID=%s".printf(dev.uuid);
				}
			}
		}

		foreach(var entry in crypttab){

			if (!entry.device.up().contains("UUID=") && !entry.device.down().has_prefix("/dev/disk/")){

				var dev = Device.find_device_in_list(devices, entry.device);
				if ((dev != null) && (dev.uuid.length > 0)){
					entry.device = "UUID=%s".printf(dev.uuid);
				}
			}
		}
	}

	// write ---------------------------
	
	public bool save_fstab_file(Gee.ArrayList<FsTabEntry> list){
		
		string txt = "# <file system> <mount point> <type> <options> <dump> <pass>\n\n";

		bool found_root = false;

		list.sort((a,b)=>{ return strcmp(a.mount_point, b.mount_point); }); // sorting required
		
		foreach(var entry in list){
			
			txt += "%s\n".printf(entry.get_line());
			
			if (entry.mount_point == "/"){
				found_root = true;
			}
		}

		if (found_root){

			var t = Time.local (time_t ());

			string file_path = "/etc/fstab";

			if (basepath.length > 1){
				file_path = path_combine(basepath, file_path);
			}
		
			string cmd = "mv -vf %s %s.bkup.%s".printf(file_path, file_path, t.format("%Y-%d-%m_%H-%M-%S"));
			Posix.system(cmd);
		
			bool ok = file_write(file_path, txt);

			if (ok){ log_msg("%s: %s".printf(_("Saved"), file_path)); }
			
			return ok;
		}
		else{
			log_error(_("Critical: New fstab does not have entry for root mount point (!). Existing file will not be changed."));
		}

		return false;
	}

	public bool save_crypttab_file(Gee.ArrayList<CryptTabEntry> list){
		
		string txt = "# <target name> <source device> <key file> <options>\n\n";

		//list.sort((a,b)=>{ return strcmp(a.name, b.name); }); // sorting not required and may cause side-effects
		
		foreach(var entry in list){
			
			txt += "%s\n".printf(entry.get_line());
		}
		
		var t = Time.local (time_t ());

		string file_path = "/etc/crypttab";

		if (basepath.length > 1){
			file_path = path_combine(basepath, file_path);
		}
		
		string cmd = "mv -vf %s %s.bkup.%s".printf(file_path, file_path, t.format("%Y-%d-%m_%H-%M-%S"));
		Posix.system(cmd);
		
		bool ok = file_write(file_path, txt);

		if (ok){ log_msg("%s: %s".printf(_("Saved"), file_path)); }
		
		return ok;
	}

	// helpers -------------------------

	public bool root_on_btrfs_subvolume(){

		foreach(var entry in fstab){
			
			if ((entry.mount_point == "/") && (entry.fs_type == "btrfs") && entry.options.contains("subvol=")){

				return true;
			}
		}

		return false;
	}

	public FsTabEntry? get_entry_by_path(string mount_path){

		foreach(var entry in fstab){
			
			if (entry.mount_point == mount_path){

				return entry;
			}
		}

		return null;
	}
	
}
