extends Node

var _update_queue : Array[_UpdateObject]
var max_age := 100 # in ms
var max_sectors_per_frame := 2

class _UpdateObject:
	var sector : Sector
	var birthday : int
	
	func _init(p_sector):
		self.sector = p_sector
		birthday = Time.get_ticks_msec()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var sectors_committed := 0
	var time_start = Time.get_ticks_usec()
	var time = Time.get_ticks_msec()
	while not _update_queue.is_empty() and (sectors_committed < max_sectors_per_frame or time - _update_queue.front().birthday > max_age):
		var target := _update_queue.pop_front() as _UpdateObject
		target.sector.commit_changes()
		sectors_committed += 1
	var time_end = Time.get_ticks_usec()
	if sectors_committed > 0:
		print("Committed %d sectors in %dus" % [sectors_committed, time_end - time_start])


## WARNING NOT THREAD SAFE
func request_update(sector: Sector):
	_update_queue.push_back(_UpdateObject.new(sector))
