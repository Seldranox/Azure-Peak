/**
 * The base type for nearly all physical objects in SS13

 * Lots and lots of functionality lives here, although in general we are striving to move
 * as much as possible to the components/elements system
 */
/atom
	layer = TURF_LAYER
	plane = GAME_PLANE
	var/level = 2

	///If non-null, overrides a/an/some in all cases
	var/article

	///First atom flags var
	var/flags_1 = NONE
	///Intearaction flags
	var/interaction_flags_atom = NONE

	/// pass_flags that we are. If any of this matches a pass_flag on a moving thing, by default, we let them through.
	var/pass_flags_self = NONE

	///Reagents holder
	var/datum/reagents/reagents = null

	///This atom's HUD (med/sec, etc) images. Associative list.
	var/list/image/hud_list = null
	///HUD images that this atom can provide.
	var/list/hud_possible

	///Value used to increment ex_act() if reactionary_explosions is on
	var/explosion_block = 0

	/**
	 * used to store the different colors on an atom
	 *
	 * its inherent color, the colored paint applied on it, special color effect etc...
	 */
	var/list/atom_colours


/// Last name used to calculate a color for the chatmessage overlays
	var/chat_color_name
	/// Last color calculated for the the chatmessage overlays
	var/chat_color
	/// A luminescence-shifted value of the last color calculated for chatmessage overlays
	var/chat_color_darkened

	var/voicecolor_override

	///overlays that should remain on top and not normally removed when using cut_overlay functions, like c4.
	var/list/priority_overlays
	/// a very temporary list of overlays to remove
	var/list/remove_overlays
	/// a very temporary list of overlays to add
	var/list/add_overlays

	///vis overlays managed by SSvis_overlays to automaticaly turn them like other overlays
	var/list/managed_vis_overlays
	///overlays managed by update_overlays() to prevent removing overlays that weren't added by the same proc
	var/list/managed_overlays

	///Proximity monitor associated with this atom
	var/datum/proximity_monitor/proximity_monitor
	///Cooldown tick timer for buckle messages
	var/buckle_message_cooldown = 0
	///Last fingerprints to touch this atom
	var/fingerprintslast

	var/list/filter_data //For handling persistent filters

	///Economy cost of item
	var/custom_price
	///Economy cost of item in premium vendor
	var/custom_premium_price

	//List of datums orbiting this atom
	var/datum/component/orbiter/orbiters

	/// Will move to flags_1 when i can be arsed to (2019, has not done so)
	var/rad_flags = NONE

	///Bitfield for how the atom handles materials.
	var/material_flags = NONE
	///Modifier that raises/lowers the effect of the amount of a material, prevents small and easy to get items from being death machines.
	var/material_modifier = 1

	var/datum/wires/wires = null

	var/list/alternate_appearances

	///AI controller that controls this atom. type on init, then turned into an instance during runtime
	var/datum/ai_controller/ai_controller

	// Use SET_BASE_PIXEL(x, y) to set these in typepath definitions, it'll handle pixel_x and y for you
	///Default pixel x shifting for the atom's icon.
	var/base_pixel_x = 0
	///Default pixel y shifting for the atom's icon.
	var/base_pixel_y = 0

/**
 * Called when an atom is created in byond (built in engine proc)
 *
 * Not a lot happens here in SS13 code, as we offload most of the work to the
 * [Intialization](atom.html#proc/Initialize) proc, mostly we run the preloader
 * if the preloader is being used and then call InitAtom of which the ultimate
 * result is that the Intialize proc is called.
 *
 * We also generate a tag here if the DF_USE_TAG flag is set on the atom
 */
/atom/New(loc, ...)
	//atom creation method that preloads variables at creation
	if(GLOB.use_preloader && (src.type == GLOB._preloader.target_path))//in case the instanciated atom is creating other atoms in New()
		world.preloader_load(src)

	if(datum_flags & DF_USE_TAG)
		GenerateTag()

	var/do_initialize = SSatoms.initialized
	if(do_initialize != INITIALIZATION_INSSATOMS)
		args[1] = do_initialize == INITIALIZATION_INNEW_MAPLOAD
		if(SSatoms.InitAtom(src, args))
			//we were deleted
			return

/**
 * The primary method that objects are setup in SS13 with
 *
 * we don't use New as we have better control over when this is called and we can choose
 * to delay calls or hook other logic in and so forth
 *
 * During roundstart map parsing, atoms are queued for intialization in the base atom/New(),
 * After the map has loaded, then Initalize is called on all atoms one by one. NB: this
 * is also true for loading map templates as well, so they don't Initalize until all objects
 * in the map file are parsed and present in the world
 *
 * If you're creating an object at any point after SSInit has run then this proc will be
 * immediately be called from New.
 *
 * mapload: This parameter is true if the atom being loaded is either being intialized during
 * the Atom subsystem intialization, or if the atom is being loaded from the map template.
 * If the item is being created at runtime any time after the Atom subsystem is intialized then
 * it's false.
 *
 * You must always call the parent of this proc, otherwise failures will occur as the item
 * will not be seen as initalized (this can lead to all sorts of strange behaviour, like
 * the item being completely unclickable)
 *
 * You must not sleep in this proc, or any subprocs
 *
 * Any parameters from new are passed through (excluding loc), naturally if you're loading from a map
 * there are no other arguments
 *
 * Must return an [initialization hint](code/__DEFINES/subsystems.html) or a runtime will occur.
 *
 * Note: the following functions don't call the base for optimization and must copypasta handling:
 * * /turf/Initialize
 * * /turf/open/space/Initialize
 */
/atom/proc/Initialize(mapload, ...)
	SHOULD_NOT_SLEEP(TRUE)
	SHOULD_CALL_PARENT(TRUE)
	if(flags_1 & INITIALIZED_1)
		stack_trace("Warning: [src]([type]) initialized multiple times!")
	flags_1 |= INITIALIZED_1

	//atom color stuff
	if(color)
		add_atom_colour(color, FIXED_COLOUR_PRIORITY)

	if (light_system == STATIC_LIGHT && light_power && (light_inner_range || light_outer_range))
		update_light()

	if (opacity && isturf(loc))
		var/turf/T = loc
		T.has_opaque_atom = TRUE // No need to recalculate it in this case, it's guaranteed to be on afterwards anyways.

	if (canSmoothWith)
		canSmoothWith = typelist("canSmoothWith", canSmoothWith)

	ComponentInitialize()
	InitializeAIController()

	return INITIALIZE_HINT_NORMAL

/**
 * Late Intialization, for code that should run after all atoms have run Intialization
 *
 * To have your LateIntialize proc be called, your atoms [Initalization](atom.html#proc/Initialize)
 *  proc must return the hint
 * [INITIALIZE_HINT_LATELOAD](code/__DEFINES/subsystems.html#define/INITIALIZE_HINT_LATELOAD)
 * otherwise you will never be called.
 *
 * useful for doing things like finding other machines on GLOB.machines because you can guarantee
 * that all atoms will actually exist in the "WORLD" at this time and that all their Intialization
 * code has been run
 */
/atom/proc/LateInitialize()
	set waitfor = FALSE

/// Put your AddComponent() calls here
/atom/proc/ComponentInitialize()
	return

/**
 * Top level of the destroy chain for most atoms
 *
 * Cleans up the following:
 * * Removes alternate apperances from huds that see them
 * * qdels the reagent holder from atoms if it exists
 * * clears the orbiters list
 * * clears overlays and priority overlays
 * * clears the light object
 */
/atom/Destroy()
	if(alternate_appearances)
		for(var/K in alternate_appearances)
			var/datum/atom_hud/alternate_appearance/AA = alternate_appearances[K]
			AA.remove_from_hud(src)

	if(reagents)
		qdel(reagents)

	orbiters = null // The component is attached to us normaly and will be deleted elsewhere

	LAZYCLEARLIST(overlays)
	LAZYCLEARLIST(priority_overlays)

	QDEL_NULL(light)
	QDEL_NULL(ai_controller)

	return ..()

/atom/proc/handle_ricochet(obj/projectile/P)
	return

///Can the mover object pass this atom, while heading for the target turf
/atom/proc/CanPass(atom/movable/mover, turf/target)
	if(mover.pass_flags & pass_flags_self)
		return TRUE
	if(mover.throwing && (pass_flags_self & LETPASSTHROW))
		return TRUE
	return !density

/**
 * Is this atom currently located on centcom
 *
 * Specifically, is it on the z level and within the centcom areas
 *
 * You can also be in a shuttleshuttle during endgame transit
 *
 * Used in gamemode to identify mobs who have escaped and for some other areas of the code
 * who don't want atoms where they shouldn't be
 */
/atom/proc/onCentCom()
	var/turf/T = get_turf(src)
	if(!T)
		return FALSE

	if(!is_centcom_level(T.z))//if not, don't bother
		return FALSE

	//Check for centcom itself
	if(istype(T.loc, /area/centcom))
		return TRUE

/**
 * Ensure a list of atoms/reagents exists inside this atom
 *
 * Goes throught he list of passed in parts, if they're reagents, adds them to our reagent holder
 * creating the reagent holder if it exists.
 *
 * If the part is a moveable atom and the  previous location of the item was a mob/living,
 * it calls the inventory handler transferItemToLoc for that mob/living and transfers the part
 * to this atom
 *
 * Otherwise it simply forceMoves the atom into this atom
 */
/atom/proc/CheckParts(list/parts_list, datum/crafting_recipe/R)
	for(var/A in parts_list)
		if(istype(A, /datum/reagent))
			if(!reagents)
				reagents = new()
			reagents.reagent_list.Add(A)
			reagents.conditional_update()
		else if(ismovableatom(A))
			var/atom/movable/M = A
			if(isliving(M.loc))
				var/mob/living/L = M.loc
				L.transferItemToLoc(M, src)
			else
				M.forceMove(src)

/obj/item/CheckParts(list/parts_list, datum/crafting_recipe/R)
	..()
	if(R)
		if(R.sellprice)
			sellprice = R.sellprice
			randomize_price()

///Hook for multiz???
/atom/proc/update_multiz(prune_on_fail = FALSE)
	return FALSE

///Check if this atoms eye is still alive (probably)
/atom/proc/check_eye(mob/user)
	return

/atom/proc/Bumped(atom/movable/AM)
	set waitfor = FALSE
	SEND_SIGNAL(src, COMSIG_ATOM_BUMPED, AM)

/// Convenience proc to see if a container is open for chemistry handling
/atom/proc/is_open_container()
	return is_refillable() && is_drainable()

/// Is this atom injectable into other atoms
/atom/proc/is_injectable(mob/user, allowmobs = TRUE)
	return reagents && (reagents.flags & (INJECTABLE | REFILLABLE))

/// Can we draw from this atom with an injectable atom
/atom/proc/is_drawable(mob/user, allowmobs = TRUE)
	return reagents && (reagents.flags & (DRAWABLE | DRAINABLE))

/// Can this atoms reagents be refilled
/atom/proc/is_refillable()
	testing("isrefill")
	return reagents && (reagents.flags & REFILLABLE)

/// Is this atom drainable of reagents
/atom/proc/is_drainable()
	testing("isdrain")
	return reagents && (reagents.flags & DRAINABLE)

/// Are you allowed to drop this atom
/atom/proc/AllowDrop()
	return FALSE

/atom/proc/CheckExit()
	return 1

///Is this atom within 1 tile of another atom
/atom/proc/HasProximity(atom/movable/AM as mob|obj)
	return

/**
 * React to an EMP of the given severity
 *
 * Default behaviour is to send the COMSIG_ATOM_EMP_ACT signal
 *
 * If the signal does not return protection, and there are attached wires then we call
 * emp_pulse() on the wires
 *
 * We then return the protection value
 */
/atom/proc/emp_act(severity)
	var/protection = SEND_SIGNAL(src, COMSIG_ATOM_EMP_ACT, severity)
	return protection // Pass the protection value collected here upwards

/**
 * React to a hit by a projectile object
 *
 * Default behaviour is to send the COMSIG_ATOM_BULLET_ACT and then call on_hit() on the projectile
 */
/atom/proc/bullet_act(obj/projectile/P, def_zone)
	SEND_SIGNAL(src, COMSIG_ATOM_BULLET_ACT, P, def_zone)
	. = P.on_hit(src, 0, def_zone)

///Return true if we're inside the passed in atom
/atom/proc/in_contents_of(container)//can take class or object instance as argument
	if(ispath(container))
		if(istype(src.loc, container))
			return TRUE
	else if(src in container)
		return TRUE
	return FALSE

/**
 * Get the name of this object for examine
 *
 * You can override what is returned from this proc by registering to listen for the
 * COMSIG_ATOM_GET_EXAMINE_NAME signal
 */
/atom/proc/get_examine_name(mob/user)
	. = "\a [src]"
	var/list/override = list(gender == PLURAL ? "some" : "a", " ", "[name]")
	if(article)
		. = "[article] [src]"
		override[EXAMINE_POSITION_ARTICLE] = article
	if(SEND_SIGNAL(src, COMSIG_ATOM_GET_EXAMINE_NAME, user, override) & COMPONENT_EXNAME_CHANGED)
		. = override.Join("")

///Generate the full examine string of this atom (including icon for goonchat)
/atom/proc/get_examine_string(mob/user, thats = FALSE)
	return "[thats? "That's ":""][get_examine_name(user)]"

/atom/proc/get_inspect_button()
	return ""

/**
 * Called when a mob examines (shift click or verb) this atom
 *
 * Default behaviour is to get the name and icon of the object and it's reagents where
 * the TRANSPARENT flag is set on the reagents holder
 *
 * Produces a signal COMSIG_PARENT_EXAMINE
 */
/atom/proc/examine(mob/user)
	. = list("[get_examine_string(user, TRUE)].[get_inspect_button()]")

	if(desc)
		. += span_info("[desc]")

	if(reagents)
		if(reagents.flags & TRANSPARENT)
			if(length(reagents.reagent_list))
				if(user.can_see_reagents() || (user.Adjacent(src) && (user.get_skill_level(/datum/skill/craft/alchemy) >= 2 || HAS_TRAIT(user, TRAIT_CICERONE)))) //Show each individual reagent
					. += "It contains:"
					for(var/datum/reagent/R in reagents.reagent_list)
						. += "[round(R.volume / 3, 0.1)] oz of <font color=[R.color]>[R.name]</font>"
				else //Otherwise, just show the total volume
					var/total_volume = 0
					var/reagent_color
					for(var/datum/reagent/R in reagents.reagent_list)
						total_volume += R.volume
					reagent_color = mix_color_from_reagents(reagents.reagent_list)
					if(total_volume / 3 < 1)
						. += "It contains less than 1 oz of <font color=[reagent_color]>something.</font>"
					else
						. += "It contains [round(total_volume / 3)] oz of <font color=[reagent_color]>something.</font>"
			else
				. += "Nothing."
		else if(reagents.flags & AMOUNT_VISIBLE)
			if(reagents.total_volume)
				. += span_notice("It has [round(reagents.total_volume / 3)] oz left.")
			else
				. += span_danger("It's empty.")

	SEND_SIGNAL(src, COMSIG_PARENT_EXAMINE, user, .)

/// Updates the icon of the atom
/atom/proc/update_icon()
	var/signalOut = SEND_SIGNAL(src, COMSIG_ATOM_UPDATE_ICON)

	if(!(signalOut & COMSIG_ATOM_NO_UPDATE_ICON_STATE))
		update_icon_state()

	if(!(signalOut & COMSIG_ATOM_NO_UPDATE_OVERLAYS))
		var/list/new_overlays = update_overlays()
		if(managed_overlays)
			cut_overlay(managed_overlays)
			managed_overlays = null
		if(length(new_overlays))
			managed_overlays = new_overlays
			add_overlay(new_overlays)

/// Updates the icon state of the atom
/atom/proc/update_icon_state()

/// Updates the overlays of the atom
/atom/proc/update_overlays()
	SHOULD_CALL_PARENT(TRUE)
	. = list()
	SEND_SIGNAL(src, COMSIG_ATOM_UPDATE_OVERLAYS, .)

/**
 * An atom we are buckled or is contained within us has tried to move
 *
 * Default behaviour is to send a warning that the user can't move while buckled as long
 * as the buckle_message_cooldown has expired (50 ticks)
 */
/atom/proc/relaymove(mob/user)
	if(buckle_message_cooldown <= world.time)
		buckle_message_cooldown = world.time + 50
		to_chat(user, "<span class='warning'>I should try resisting.</span>")
	return

/// Handle what happens when your contents are exploded by a bomb
/atom/proc/contents_explosion(severity, target)
	return //For handling the effects of explosions on contents that would not normally be effected

/**
 * React to being hit by an explosion
 *
 * Default behaviour is to call contents_explosion() and send the COMSIG_ATOM_EX_ACT signal
 */
/atom/proc/ex_act(severity, target, epicenter, devastation_range, heavy_impact_range, light_impact_range, flame_range)
	set waitfor = FALSE
	contents_explosion(severity, target, epicenter, devastation_range, heavy_impact_range, light_impact_range, flame_range)
	SEND_SIGNAL(src, COMSIG_ATOM_EX_ACT, severity, target, epicenter, devastation_range, heavy_impact_range, light_impact_range, flame_range)

/atom/proc/fire_act(added, maxstacks)
	SEND_SIGNAL(src, COMSIG_ATOM_FIRE_ACT, added, maxstacks)
	return

/**
 * React to being hit by a thrown object
 *
 * Default behaviour is to call hitby_react() on ourselves after 2 seconds if we are dense
 * and under normal gravity.
 *
 * Im not sure why this the case, maybe to prevent lots of hitby's if the thrown object is
 * deleted shortly after hitting something (during explosions or other massive events that
 * throw lots of items around - singularity being a notable example)
 */
/atom/proc/hitby(atom/movable/AM, skipcatch, hitpush, blocked, datum/thrownthing/throwingdatum, damage_flag = "blunt")
	SEND_SIGNAL(src, COMSIG_ATOM_HITBY, AM, skipcatch, hitpush, blocked, throwingdatum, damage_flag)
	if(density && !has_gravity(AM)) //thrown stuff bounces off dense stuff in no grav, unless the thrown stuff ends up inside what it hit(embedding, bola, etc...).
		addtimer(CALLBACK(src, PROC_REF(hitby_react), AM), 2)

/**
 * We have have actually hit the passed in atom
 *
 * Default behaviour is to move back from the item that hit us
 */
/atom/proc/hitby_react(atom/movable/AM)
	if(AM && isturf(AM.loc))
		step(AM, turn(AM.dir, 180))

///Handle the atom being slipped over
/atom/proc/handle_slip(mob/living/carbon/C, knockdown_amount, obj/O, lube, paralyze, force_drop)
	return

///returns the mob's dna info as a list, to be inserted in an object's blood_DNA list
/mob/living/proc/get_blood_dna_list()
	if(get_blood_id() != /datum/reagent/blood)
		return
	return list("ANIMAL DNA" = "Y-")

///Get the mobs dna list
/mob/living/carbon/get_blood_dna_list()
	if(get_blood_id() != /datum/reagent/blood)
		return
	var/list/blood_dna = list()
	if(dna)
		blood_dna[dna.unique_enzymes] = dna.blood_type
	else
		blood_dna["UNKNOWN DNA"] = "X*"
	return blood_dna

///to add a mob's dna info into an object's blood_dna list.
/atom/proc/transfer_mob_blood_dna(mob/living/L)
	// Returns 0 if we have that blood already
	var/new_blood_dna = L.get_blood_dna_list()
	if(!new_blood_dna)
		return FALSE
	var/old_length = blood_DNA_length()
	add_blood_DNA(new_blood_dna)
	if(blood_DNA_length() == old_length)
		return FALSE
	return TRUE

///to add blood from a mob onto something, and transfer their dna info
/atom/proc/add_mob_blood(mob/living/M)
	var/list/blood_dna = M.get_blood_dna_list()
	if(!blood_dna)
		return FALSE
	return add_blood_DNA(blood_dna)

///Called when gravity returns after floating I think
/atom/proc/handle_fall()
	return

/**
 * Respond to acid being used on our atom
 *
 * Default behaviour is to send COMSIG_ATOM_ACID_ACT and return
 */
/atom/proc/acid_act(acidpwr, acid_volume)
	SEND_SIGNAL(src, COMSIG_ATOM_ACID_ACT, acidpwr, acid_volume)

/**
 * Respond to an emag being used on our atom
 *
 * Default behaviour is to send COMSIG_ATOM_EMAG_ACT and return
 */
/atom/proc/emag_act(mob/user)
	SEND_SIGNAL(src, COMSIG_ATOM_EMAG_ACT, user)

/**
 * Respond to narsie eating our atom
 *
 * Default behaviour is to send COMSIG_ATOM_NARSIE_ACT and return
 */
/atom/proc/narsie_act()
	SEND_SIGNAL(src, COMSIG_ATOM_NARSIE_ACT)

/**
 * Implement the behaviour for when a user click drags a storage object to your atom
 *
 * This behaviour is usually to mass transfer, but this is no longer a used proc as it just
 * calls the underyling /datum/component/storage dump act if a component exists
 *
 * TODO these should be purely component items that intercept the atom clicks higher in the
 * call chain
 */
/atom/proc/storage_contents_dump_act(obj/item/storage/src_object, mob/user)
	if(GetComponent(/datum/component/storage))
		return component_storage_contents_dump_act(src_object, user)
	return FALSE

/**
 * Implement the behaviour for when a user click drags another storage item to you
 *
 * In this case we get as many of the tiems from the target items compoent storage and then
 * put everything into ourselves (or our storage component)
 *
 * TODO these should be purely component items that intercept the atom clicks higher in the
 * call chain
 */
/atom/proc/component_storage_contents_dump_act(datum/component/storage/src_object, mob/user)
	if(src_object.parent == src)
		return
	var/list/things = src_object.contents()
	var/datum/progressbar/progress = new(user, things.len, src)
	var/datum/component/storage/STR = GetComponent(/datum/component/storage)
	while (do_after(user, 10, TRUE, src, FALSE, CALLBACK(STR, TYPE_PROC_REF(/datum/component/storage, handle_mass_item_insertion), things, src_object, user, progress)))
		stoplag(1)
	qdel(progress)
	to_chat(user, "<span class='notice'>I dump as much of [src_object.parent]'s contents [STR.insert_preposition]to [src] as I can.</span>")
	STR.orient2hud(user)
	STR.update_icon()
	src_object.update_icon()
	src_object.orient2hud(user)
	if(user.active_storage) //refresh the HUD to show the transfered contents
		user.active_storage.close(user)
		user.active_storage.show_to(user)
	return TRUE

///Get the best place to dump the items contained in the source storage item?
/atom/proc/get_dumping_location(obj/item/storage/source,mob/user)
	return null

/**
 * This proc is called when an atom in our contents has it's Destroy() called
 *
 * Default behaviour is to simply send COMSIG_ATOM_CONTENTS_DEL
 */
/atom/proc/handle_atom_del(atom/A)
	SEND_SIGNAL(src, COMSIG_ATOM_CONTENTS_DEL, A)

/**
 * called when the turf the atom resides on is ChangeTurfed
 *
 * Default behaviour is to loop through atom contents and call their HandleTurfChange() proc
 */
/atom/proc/HandleTurfChange(turf/T)
	for(var/a in src)
		var/atom/A = a
		A.HandleTurfChange(T)

/**
 * the vision impairment to give to the mob whose perspective is set to that atom
 *
 * (e.g. an unfocused camera giving you an impaired vision when looking through it)
 */
/atom/proc/get_remote_view_fullscreens(mob/user)
	return

/**
 * the sight changes to give to the mob whose perspective is set to that atom
 *
 * (e.g. A mob with nightvision loses its nightvision while looking through a normal camera)
 */
/atom/proc/update_remote_sight(mob/living/user)
	return


/**
 * Hook for running code when a dir change occurs
 *
 * Not recommended to use, listen for the COMSIG_ATOM_DIR_CHANGE signal instead (sent by this proc)
 */
/atom/proc/setDir(newdir)
	SEND_SIGNAL(src, COMSIG_ATOM_DIR_CHANGE, dir, newdir)
	dir = newdir

/**
 * Called when the atom log's in or out
 *
 * Default behaviour is to call on_log on the location this atom is in
 */
/atom/proc/on_log(login)
	if(loc)
		loc.on_log(login)


/*
	Atom Colour Priority System
	A System that gives finer control over which atom colour to colour the atom with.
	The "highest priority" one is always displayed as opposed to the default of
	"whichever was set last is displayed"
*/


///Adds an instance of colour_type to the atom's atom_colours list
/atom/proc/add_atom_colour(coloration, colour_priority)
	if(!atom_colours || !atom_colours.len)
		atom_colours = list()
		atom_colours.len = COLOUR_PRIORITY_AMOUNT //four priority levels currently.
	if(!coloration)
		return
	if(colour_priority > atom_colours.len)
		return
	atom_colours[colour_priority] = coloration
	update_atom_colour()


///Removes an instance of colour_type from the atom's atom_colours list
/atom/proc/remove_atom_colour(colour_priority, coloration)
	if(!atom_colours)
		atom_colours = list()
		atom_colours.len = COLOUR_PRIORITY_AMOUNT //four priority levels currently.
	if(colour_priority > atom_colours.len)
		return
	if(coloration && atom_colours[colour_priority] != coloration)
		return //if we don't have the expected color (for a specific priority) to remove, do nothing
	atom_colours[colour_priority] = null
	update_atom_colour()


///Resets the atom's color to null, and then sets it to the highest priority colour available
/atom/proc/update_atom_colour()
	if(!atom_colours)
		atom_colours = list()
		atom_colours.len = COLOUR_PRIORITY_AMOUNT //four priority levels currently.
	color = null
	for(var/C in atom_colours)
		if(islist(C))
			var/list/L = C
			if(L.len)
				color = L
				return
		else if(C)
			color = C
			return

/**
 * call back when a var is edited on this atom
 *
 * Can be used to implement special handling of vars
 *
 * At the atom level, if you edit a var named "color" it will add the atom colour with
 * admin level priority to the atom colours list
 *
 * Also, if GLOB.Debug2 is FALSE, it sets the ADMIN_SPAWNED_1 flag on flags_1, which signifies
 * the object has been admin edited
 */
/atom/vv_edit_var(var_name, var_value)
	if(!GLOB.Debug2)
		flags_1 |= ADMIN_SPAWNED_1
	. = ..()
	switch(var_name)
		if("color")
			add_atom_colour(color, ADMIN_COLOUR_PRIORITY)

/**
 * Return the markup to for the dropdown list for the VV panel for this atom
 *
 * Override in subtypes to add custom VV handling in the VV panel
 */
/atom/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION("", "---------")
	if(!ismovableatom(src))
		var/turf/curturf = get_turf(src)
		if(curturf)
			. += "<option value='?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[curturf.x];Y=[curturf.y];Z=[curturf.z]'>Jump To</option>"
	VV_DROPDOWN_OPTION(VV_HK_MODIFY_TRANSFORM, "Modify Transform")
	VV_DROPDOWN_OPTION(VV_HK_ADD_REAGENT, "Add Reagent")
	VV_DROPDOWN_OPTION(VV_HK_TRIGGER_EXPLOSION, "Explosion")
	VV_DROPDOWN_OPTION(VV_HK_ADD_AI, "Add AI controller")

/atom/vv_do_topic(list/href_list)
	. = ..()
	if(href_list[VV_HK_ADD_REAGENT] && check_rights(R_VAREDIT))
		if(!reagents)
			var/amount = input(usr, "Specify the reagent size of [src]", "Set Reagent Size", 50) as num|null
			if(amount)
				create_reagents(amount)

		if(reagents)
			var/chosen_id
			switch(alert(usr, "Choose a method.", "Add Reagents", "Search", "Choose from a list", "I'm feeling lucky"))
				if("Search")
					var/valid_id
					while(!valid_id)
						chosen_id = input(usr, "Enter the ID of the reagent you want to add.", "Search reagents") as null|text
						if(isnull(chosen_id)) //Get me out of here!
							break
						if (!ispath(text2path(chosen_id)))
							chosen_id = pick_closest_path(chosen_id, make_types_fancy(subtypesof(/datum/reagent)))
							if (ispath(chosen_id))
								valid_id = TRUE
						else
							valid_id = TRUE
						if(!valid_id)
							to_chat(usr, "<span class='warning'>A reagent with that ID doesn't exist!</span>")
				if("Choose from a list")
					chosen_id = input(usr, "Choose a reagent to add.", "Choose a reagent.") as null|anything in sortList(subtypesof(/datum/reagent), GLOBAL_PROC_REF(cmp_typepaths_asc))
				if("I'm feeling lucky")
					chosen_id = pick(subtypesof(/datum/reagent))
			if(chosen_id)
				var/amount = input(usr, "Choose the amount to add.", "Choose the amount.", reagents.maximum_volume) as num|null
				if(amount)
					reagents.add_reagent(chosen_id, amount)
					log_admin("[key_name(usr)] has added [amount] units of [chosen_id] to [src]")
					message_admins("<span class='notice'>[key_name(usr)] has added [amount] units of [chosen_id] to [src]</span>")
	if(href_list[VV_HK_TRIGGER_EXPLOSION] && check_rights(R_FUN))
		usr.client.cmd_admin_explosion(src)
	if(href_list[VV_HK_MODIFY_TRANSFORM] && check_rights(R_VAREDIT))
		var/result = input(usr, "Choose the transformation to apply","Transform Mod") as null|anything in list("Scale","Translate","Rotate")
		var/matrix/M = transform
		switch(result)
			if("Scale")
				var/x = input(usr, "Choose x mod","Transform Mod") as null|num
				var/y = input(usr, "Choose y mod","Transform Mod") as null|num
				if(!isnull(x) && !isnull(y))
					transform = M.Scale(x,y)
			if("Translate")
				var/x = input(usr, "Choose x mod","Transform Mod") as null|num
				var/y = input(usr, "Choose y mod","Transform Mod") as null|num
				if(!isnull(x) && !isnull(y))
					transform = M.Translate(x,y)
			if("Rotate")
				var/angle = input(usr, "Choose angle to rotate","Transform Mod") as null|num
				if(!isnull(angle))
					transform = M.Turn(angle)
	if(href_list[VV_HK_AUTO_RENAME] && check_rights(R_VAREDIT))
		var/newname = input(usr, "What do you want to rename this to?", "Automatic Rename") as null|text
		if(newname)
			vv_auto_rename(newname)

/atom/vv_get_header()
	. = ..()
	var/refid = REF(src)
	. += "[VV_HREF_TARGETREF(refid, VV_HK_AUTO_RENAME, "<b id='name'>[src]</b>")]"
	. += "<br><font size='1'><a href='?_src_=vars;[HrefToken()];rotatedatum=[refid];rotatedir=left'><<</a> <a href='?_src_=vars;[HrefToken()];datumedit=[refid];varnameedit=dir' id='dir'>[dir2text(dir) || dir]</a> <a href='?_src_=vars;[HrefToken()];rotatedatum=[refid];rotatedir=right'>>></a></font>"

///Where atoms should drop if taken from this atom
/atom/proc/drop_location()
	var/atom/L = loc
	if(!L)
		return null
	return L.AllowDrop() ? L : L.drop_location()

/atom/proc/vv_auto_rename(newname)
	name = newname

/**
 * An atom has entered this atom's contents
 *
 * Default behaviour is to send the COMSIG_ATOM_ENTERED
 */
/atom/Entered(atom/movable/AM, atom/oldLoc)
	SEND_SIGNAL(src, COMSIG_ATOM_ENTERED, AM, oldLoc)

/**
 * An atom is attempting to exit this atom's contents
 *
 * Default behaviour is to send the COMSIG_ATOM_EXIT
 *
 * Return value should be set to FALSE if the moving atom is unable to leave,
 * otherwise leave value the result of the parent call
 */
/atom/Exit(atom/movable/AM, atom/newLoc)
	. = ..()
	if(SEND_SIGNAL(src, COMSIG_ATOM_EXIT, AM, newLoc) & COMPONENT_ATOM_BLOCK_EXIT)
		return FALSE

/**
 * An atom has exited this atom's contents
 *
 * Default behaviour is to send the COMSIG_ATOM_EXITED
 */
/atom/Exited(atom/movable/AM, atom/newLoc)
	SEND_SIGNAL(src, COMSIG_ATOM_EXITED, AM, newLoc)

///Return atom temperature
/atom/proc/return_temperature()
	return

/**
 *Tool behavior procedure. Redirects to tool-specific procs by default.
 *
 * You can override it to catch all tool interactions, for use in complex deconstruction procs.
 *
 * Must return  parent proc ..() in the end if overridden
 */
/atom/proc/tool_act(mob/living/user, obj/item/I, tool_type)
	switch(tool_type)
		if(TOOL_CROWBAR)
			. |= crowbar_act(user, I)
		if(TOOL_MULTITOOL)
			. |= multitool_act(user, I)
		if(TOOL_SCREWDRIVER)
			. |= screwdriver_act(user, I)
		if(TOOL_WRENCH)
			. |= wrench_act(user, I)
		if(TOOL_WIRECUTTER)
			. |= wirecutter_act(user, I)
		if(TOOL_WELDER)
			. |= welder_act(user, I)
		if(TOOL_ANALYZER)
			. |= analyzer_act(user, I)
	if(. & COMPONENT_BLOCK_TOOL_ATTACK)
		return TRUE

//! Tool-specific behavior procs. They send signals, so try to call ..()
///

///Crowbar act
/atom/proc/crowbar_act(mob/living/user, obj/item/I)
	return SEND_SIGNAL(src, COMSIG_ATOM_CROWBAR_ACT, user, I)

///Multitool act
/atom/proc/multitool_act(mob/living/user, obj/item/I)
	return SEND_SIGNAL(src, COMSIG_ATOM_MULTITOOL_ACT, user, I)

///Check if the multitool has an item in it's data buffer
/atom/proc/multitool_check_buffer(user, obj/item/I, silent = FALSE)
	if(!istype(I, /obj/item/multitool))
		if(user && !silent)
			to_chat(user, "<span class='warning'>[I] has no data buffer!</span>")
		return FALSE
	return TRUE

///Screwdriver act
/atom/proc/screwdriver_act(mob/living/user, obj/item/I)
	return SEND_SIGNAL(src, COMSIG_ATOM_SCREWDRIVER_ACT, user, I)

///Wrench act
/atom/proc/wrench_act(mob/living/user, obj/item/I)
	return SEND_SIGNAL(src, COMSIG_ATOM_WRENCH_ACT, user, I)

///Wirecutter act
/atom/proc/wirecutter_act(mob/living/user, obj/item/I)
	return SEND_SIGNAL(src, COMSIG_ATOM_WIRECUTTER_ACT, user, I)

///Welder act
/atom/proc/welder_act(mob/living/user, obj/item/I)
	return SEND_SIGNAL(src, COMSIG_ATOM_WELDER_ACT, user, I)

///Analyzer act
/atom/proc/analyzer_act(mob/living/user, obj/item/I)
	return SEND_SIGNAL(src, COMSIG_ATOM_ANALYSER_ACT, user, I)

///Generate a tag for this atom
/atom/proc/GenerateTag()
	return

/// Generic logging helper
/atom/proc/log_message(message, message_type, color=null, log_globally=TRUE)
	if(!log_globally)
		return

	var/log_text = "[key_name(src)] [message] [loc_name(src)]"
	switch(message_type)
		if(LOG_SEEN)
			log_seen_internal(log_text)
		if(LOG_ATTACK)
			log_attack(log_text)
		if(LOG_SAY)
			log_say(log_text)
		if(LOG_WHISPER)
			log_whisper(log_text)
		if(LOG_EMOTE)
			log_emote(log_text)
		if(LOG_DSAY)
			log_dsay(log_text)
		if(LOG_PDA)
			log_pda(log_text)
		if(LOG_CHAT)
			log_chat(log_text)
		if(LOG_COMMENT)
			log_comment(log_text)
		if(LOG_TELECOMMS)
			log_telecomms(log_text)
		if(LOG_OOC)
			log_ooc(log_text)
		if(LOG_LOOC)
			log_looc(log_text)
		if(LOG_ADMIN)
			log_admin(log_text)
		if(LOG_ADMIN_PRIVATE)
			log_admin_private(log_text)
		if(LOG_ASAY)
			log_adminsay(log_text)
		if(LOG_OWNERSHIP)
			log_game(log_text)
		if(LOG_GAME)
			log_game(log_text)
		if(LOG_MECHA)
			log_mecha(log_text)
		else
			stack_trace("Invalid individual logging type: [message_type]. Defaulting to [LOG_GAME] (LOG_GAME).")
			log_game(log_text)

/// Helper for logging chat messages or other logs with arbitrary inputs (e.g. announcements)
/atom/proc/log_talk(message, message_type, tag=null, log_globally=TRUE, forced_by=null)
	var/prefix = tag ? "([tag]) " : ""
	var/suffix = forced_by ? " FORCED by [forced_by]" : ""
	log_message("[prefix]\"[message]\"[suffix]", message_type, log_globally=log_globally)

/// Helper for logging of messages with only one sender and receiver
/proc/log_directed_talk(atom/source, atom/target, message, message_type, tag)
	if(!tag)
		stack_trace("Unspecified tag for private message")
		tag = "UNKNOWN"

	source.log_talk(message, message_type, tag="[tag] to [key_name(target)]")
	if(source != target)
		target.log_talk(message, message_type, tag="[tag] from [key_name(source)]", log_globally=FALSE)

/**
 * Log a combat message in the attack log
 *
 * 1 argument is the actor performing the action
 * 2 argument is the target of the action
 * 3 is a verb describing the action (e.g. punched, throwed, kicked, etc.)
 * 4 is a tool with which the action was made (usually an item)
 * 5 is any additional text, which will be appended to the rest of the log line
 */
/proc/log_combat(atom/user, atom/target, what_done, atom/object=null, addition=null, log_seen = TRUE)
	var/ssource = key_name(user)
	var/starget = key_name(target)

	var/mob/living/living_target = target
	var/hp = istype(living_target) ? " (NEWHP: [living_target.health]) " : ""

	var/sobject = ""
	if(object)
		sobject = " with [object]"
	var/saddition = ""
	if(addition)
		saddition = " [addition]"

	var/postfix = "[sobject][saddition][hp]"

	var/message = "has [what_done] [starget][postfix]"
	user.log_message(message, LOG_ATTACK, color="red")

	if(log_seen)
		log_seen_viewers(user, target, message, SEEN_LOG_ATTACK)
	
	if(user != target)
		var/reverse_message = "has been [what_done] by [ssource][postfix]"
		target?.log_message(reverse_message, LOG_ATTACK, color="orange", log_globally=FALSE)

/proc/log_seen(mob/user, atom/target, list/viewers, message, seen_type)
	var/color
	switch(seen_type)
		if(SEEN_LOG_SAY)
			color = "orange"
		if(SEEN_LOG_EMOTE)
			color = "grey"
		if(SEEN_LOG_ATTACK)
			color = "red"
	var/count = 0
	var/viewer_string = ""
	for(var/mob/viewer as anything in viewers)
		if(viewer == user)
			continue
		if(!isliving(viewer))
			continue
		if(!viewer.client)
			continue
		count++
		if(count > 1)
			viewer_string += ", "
		viewer_string += key_name(viewer)
	if(target)
		if(ismob(target))
			var/mob/mob_target = target
			message += " [key_name(mob_target)]"
		else
			message += " [target]"
	user.log_message("[message] ([viewer_string])", LOG_SEEN, color=color, log_globally=FALSE)

/proc/log_seen_viewers(mob/user, mob/target, message, seen_type, vision_distance = DEFAULT_MESSAGE_RANGE)
	var/list/viewers = get_hearers_in_view(vision_distance, user)
	log_seen(user, target, viewers, message, seen_type)

/proc/log_seen_hearers(mob/user, mob/target, message, seen_type, vision_distance = DEFAULT_MESSAGE_RANGE)
	var/list/hearers = get_hearers_in_view(vision_distance, user)
	log_seen(user, target, hearers, message, seen_type)

/atom/movable/proc/add_filter(name,priority,list/params)
	if(!filter_data)
		filter_data = list()
	var/list/p = params.Copy()
	p["priority"] = priority
	filter_data[name] = p
	update_filters()

/atom/movable/proc/remove_filter(name_or_names)
	if(!filter_data)
		return

	var/list/names = islist(name_or_names) ? name_or_names : list(name_or_names)

	. = FALSE
	for(var/name in names)
		if(filter_data[name])
			filter_data -= name
			. = TRUE

	if(.)
		update_filters()
	return .

/atom/movable/proc/update_filters() //Determine which filter comes first
	filters = null                  //note, the cmp_filter is a little flimsy.
	sortTim(filter_data, /proc/cmp_filter_priority_desc, associative = TRUE) 
	for(var/f in filter_data)
		var/list/data = filter_data[f]
		var/list/arguments = data.Copy()
		arguments -= "priority"
		filters += filter(arglist(arguments))

/atom/movable/proc/get_filter(name)
	if(filter_data && filter_data[name])
		return filters[filter_data.Find(name)]

/** Update a filter's parameter and animate this change. If the filter doesn't exist we won't do anything.
 * Basically a [datum/proc/modify_filter] call but with animations. Unmodified filter parameters are kept.
 *
 * Arguments:
 * * name - Filter name
 * * new_params - New parameters of the filter
 * * time - time arg of the BYOND animate() proc.
 * * easing - easing arg of the BYOND animate() proc.
 * * loop - loop arg of the BYOND animate() proc.
 */
/atom/movable/proc/transition_filter(name, list/new_params, time, easing, loop)
	var/filter = get_filter(name)
	if(!filter)
		return
	// This can get injected by the filter procs, we want to support them so bye byeeeee
	new_params -= "type"
	animate(filter, new_params, time = time, easing = easing, loop = loop)
	modify_filter(name, new_params)

/** Update a filter's parameter to the new one. If the filter doesn't exist we won't do anything.
 *
 * Arguments:
 * * name - Filter name
 * * new_params - New parameters of the filter
 * * overwrite - TRUE means we replace the parameter list completely. FALSE means we only replace the things on new_params.
 */
/atom/movable/proc/modify_filter(name, list/new_params, overwrite = FALSE)
	var/filter = get_filter(name)
	if(!filter)
		return
	if(overwrite)
		filter_data[name] = new_params
	else
		for(var/thing in new_params)
			filter_data[name][thing] = new_params[thing]
	update_filters()

/atom/proc/intercept_zImpact(atom/movable/AM, levels = 1)
	. |= SEND_SIGNAL(src, COMSIG_ATOM_INTERCEPT_Z_FALL, AM, levels)

/**
 * Returns true if this atom has gravity for the passed in turf
 *
 * Sends signals COMSIG_ATOM_HAS_GRAVITY and COMSIG_TURF_HAS_GRAVITY, both can force gravity with
 * the forced gravity var
 *
 * Gravity situations:
 * * No gravity if you're not in a turf
 * * No gravity if this atom is in is a space turf
 * * Gravity if the area it's in always has gravity
 * * Gravity if there's a gravity generator on the z level
 * * Gravity if the Z level has an SSMappingTrait for ZTRAIT_GRAVITY
 * * otherwise no gravity
 */
/atom/proc/has_gravity(turf/gravity_turf)
	if(!isturf(gravity_turf))
		gravity_turf = get_turf(src)

	if(!gravity_turf)//no gravity in nullspace
		return 0

	//the list isnt created every time as this proc is very hot, its only accessed if anything is actually listening to the signal too
	var/static/list/forced_gravity = list()
	if(SEND_SIGNAL(src, COMSIG_ATOM_HAS_GRAVITY, gravity_turf, forced_gravity))
		if(!length(forced_gravity))
			SEND_SIGNAL(gravity_turf, COMSIG_TURF_HAS_GRAVITY, src, forced_gravity)

		var/max_grav = 0
		for(var/i in forced_gravity)//our gravity is the strongest return forced gravity we get
			max_grav = max(max_grav, i)
		forced_gravity.Cut()
		//cut so we can reuse the list, this is ok since forced gravity movers are exceedingly rare compared to all other movement
		return max_grav

	var/area/turf_area = gravity_turf.loc
	// force_no_gravity has been removed because this is Roguetown code
	// it'd be trivial to readd if you needed it, though
	return SSmapping.gravity_by_z_level["[gravity_turf.z]"] || turf_area.has_gravity


/**
* Instantiates the AI controller of this atom. Override this if you want to assign variables first.
*
* This will work fine without manually passing arguments.
+*/
/atom/proc/InitializeAIController()
	if(ai_controller)
		ai_controller = new ai_controller(src)

///Returns a list of all locations (except the area) the movable is within.
/proc/get_nested_locs(atom/movable/atom_on_location, include_turf = FALSE)
	. = list()
	var/atom/location = atom_on_location.loc
	var/turf/our_turf = get_turf(atom_on_location)
	while(location && location != our_turf)
		. += location
		location = location.loc
	if(our_turf && include_turf) //At this point, only the turf is left, provided it exists.
		. += our_turf
