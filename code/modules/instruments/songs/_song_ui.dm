/datum/song/tgui_data(mob/user)
	var/data[0]

	// General
	data["playing"] = playing
	data["repeat"] = repeat
	data["maxRepeats"] = max_repeats
	data["editing"] = editing
	data["lines"] = lines
	data["tempo"] = tempo
	data["minTempo"] = world.tick_lag
	data["maxTempo"] = 5 SECONDS
	data["tickLag"] = world.tick_lag
	data["help"] = help

	// Status
	var/list/allowed_instrument_names = list()
	for(var/i in allowed_instrument_ids)
		var/datum/instrument/I = SSinstruments.get_instrument(i)
		if(I)
			allowed_instrument_names += I.name
	data["allowedInstrumentNames"] = allowed_instrument_names
	data["instrumentLoaded"] = !isnull(using_instrument)
	if(using_instrument)
		data["instrument"] = using_instrument.name
	data["canNoteShift"] = can_noteshift
	if(can_noteshift)
		data["noteShift"] = note_shift
		data["noteShiftMin"] = note_shift_min
		data["noteShiftMax"] = note_shift_max
	data["sustainMode"] = sustain_mode
	switch(sustain_mode)
		if(SUSTAIN_LINEAR)
			data["sustainLinearDuration"] = sustain_linear_duration
		if(SUSTAIN_EXPONENTIAL)
			data["sustainExponentialDropoff"] = sustain_exponential_dropoff
	data["ready"] = using_instrument?.is_ready()
	data["legacy"] = legacy
	data["volume"] = volume
	data["minVolume"] = min_volume
	data["maxVolume"] = max_volume
	data["sustainDropoffVolume"] = sustain_dropoff_volume
	data["sustainHeldNote"] = full_sustain_held_note

	return data

/datum/song/tgui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/tgui_state/state = GLOB.tgui_default_state)
	ui = SStgui.try_update_ui(user, parent, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, parent, ui_key, "Instrument", parent?.name || "Instrument", 700, 500)
		ui.open()
		ui.set_autoupdate(FALSE) // NO!!! Don't auto-update this!!

/datum/song/tgui_act(action, params)
	switch(action)
		if("newsong")
			lines = new()
			tempo = sanitize_tempo(5) // default 120 BPM
			name = ""
			return TRUE
		if("import")
			var/t = ""
			do
				t = html_encode(input(usr, "Please paste the entire song, formatted:", text("[]", name), t)  as message)
				if(!in_range(parent, usr))
					return

				if(length_char(t) >= MUSIC_MAXLINES * MUSIC_MAXLINECHARS)
					var/cont = input(usr, "Your message is too long! Would you like to continue editing it?", "", "yes") in list("yes", "no")
					if(cont == "no")
						break
			while(length_char(t) > MUSIC_MAXLINES * MUSIC_MAXLINECHARS)
			parse_song(t)
		if("help")
			help = !help
			return TRUE
		if("edit")
			editing = !editing
			return TRUE
		if("repeat") //Changing this from a toggle to a number of repeats to avoid infinite loops.
			if(playing)
				return //So that people cant keep adding to repeat. If the do it intentionally, it could result in the server crashing.
			repeat = clamp(round(text2num(params["new"])), 0, max_repeats)
			return TRUE
		if("tempo")
			tempo = sanitize_tempo(text2num(params["new"]))
			return TRUE
		if("play")
			INVOKE_ASYNC(src, .proc/start_playing, usr)
		if("newline")
			var/newline = html_encode(input("Enter your line: ", parent.name) as text|null)
			if(!newline || !in_range(parent, usr))
				return
			if(length(lines) > MUSIC_MAXLINES)
				return
			if(length(newline) > MUSIC_MAXLINECHARS)
				newline = copytext(newline, 1, MUSIC_MAXLINECHARS)
			lines.Add(newline)
			return TRUE
		if("deleteline")
			var/num = round(text2num(params["line"]))
			if(num > length(lines) || num < 1)
				return
			lines.Cut(num, num + 1)
			return TRUE
		if("modifyline")
			var/num = round(text2num(params["line"]))
			var/content = stripped_input(usr, "Enter your line: ", parent.name, lines[num], MUSIC_MAXLINECHARS)
			if(!content || !in_range(parent, usr))
				return
			if(num > length(lines) || num < 1)
				return
			lines[num] = content
			return TRUE
		if("stop")
			stop_playing()
		if("setlinearfalloff")
			set_linear_falloff_duration(round(text2num(params["new"]) * 10, world.tick_lag))
			return TRUE
		if("setexpfalloff")
			set_exponential_drop_rate(round(text2num(params["new"]), 0.00001))
			return TRUE
		if("setvolume")
			set_volume(round(text2num(params["new"]), 1))
		if("setdropoffvolume")
			set_dropoff_volume(round(text2num(params["new"]), 0.01))
			return TRUE
		if("switchinstrument")
			if(!length(allowed_instrument_ids))
				return
			else if(length(allowed_instrument_ids) == 1)
				set_instrument(allowed_instrument_ids[1])
				return
			var/choice = params["name"]
			for(var/i in allowed_instrument_ids)
				var/datum/instrument/I = SSinstruments.get_instrument(i)
				if(I && I.name == choice)
					set_instrument(I)
					return TRUE
		if("setnoteshift")
			note_shift = clamp(round(text2num(params["new"])), note_shift_min, note_shift_max)
			return TRUE
		if("setsustainmode")
			var/static/list/sustain_modes
			if(!length(sustain_modes))
				sustain_modes = list("Linear" = SUSTAIN_LINEAR, "Exponential" = SUSTAIN_EXPONENTIAL)
			var/choice = params["new"]
			sustain_mode = sustain_modes[choice] || sustain_mode
			return TRUE
		if("togglesustainhold")
			full_sustain_held_note = !full_sustain_held_note
			return TRUE
		else
			return FALSE
	parent.add_fingerprint(usr)

/**
  * Parses a song the user has input into lines and stores them.
  */
/datum/song/proc/parse_song(text)
	set waitfor = FALSE
	//split into lines
	lines = splittext(text, "\n")
	if(length(lines))
		var/bpm_string = "BPM: "
		if(findtext(lines[1], bpm_string, 1, length(bpm_string) + 1))
			var/divisor = text2num(copytext(lines[1], length(bpm_string) + 1)) || 120 // default
			tempo = sanitize_tempo(600 / round(divisor, 1))
			lines.Cut(1, 2)
		else
			tempo = sanitize_tempo(5) // default 120 BPM
		if(length(lines) > MUSIC_MAXLINES)
			to_chat(usr, "Too many lines!")
			lines.Cut(MUSIC_MAXLINES + 1)
		var/linenum = 1
		for(var/l in lines)
			if(length_char(l) > MUSIC_MAXLINECHARS)
				to_chat(usr, "Line [linenum] too long!")
				lines.Remove(l)
			else
				linenum++
		SStgui.update_uis(parent)
