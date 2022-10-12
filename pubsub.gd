extends Node2D
# Adapted from the GIFT plugin's basic websocket functionality: https://github.com/issork/gift
# Twitch PubSub docs: https://dev.twitch.tv/docs/pubsub
#------------
# You need to create a Twitch Application: https://dev.twitch.tv/docs/authentication/register-app
# Generate Twitch tokens from your app: https://twitchapps.com/tokengen/ using the required scopes: https://dev.twitch.tv/docs/pubsub#topics
#------------
# To use an external file for credentials, write a file path string in cred_file, e.g. C:\Directory\File.txt. If you do not use an external file, simply leave cred_file blank.
# The format of the external file being used is a txt file using json:
# {"the_auth":"<your token>", "the_listener":"<your app name>", "the_channel":"<your channel id>",}
export(String) var cred_file := "" 
# If the cred_file variable is blank, you must enter the needed info into the variables.
export(String) var the_auth:String = ""
export(String) var the_listener:String = ""
export(String) var the_channel:String = ""
#---------------------------------------------------------------------------
# If you have multiple connections in your application, you may want to delay or stagger them when trying to connect.
export(bool) var delay_connection = true
export(float) var delay_seconds = 2.0

var SOCKET_URL = "wss://pubsub-edge.twitch.tv"
var Ping_Timer := Timer.new()
var ConnectDelay := Timer.new()
var websocket = WebSocketClient.new()
var user_regex = RegEx.new()
var twitch_restarting

signal twitch_connected
signal twitch_disconnected
signal twitch_unavailable
signal twitch_reconnect
signal login_attempt(success)
signal incoming_subs(is_gift, the_context, the_purchaser, the_recipient, the_sub_plan, the_total_months, the_streak_months, the_multi_month_buy)
signal incoming_bits(the_bits, is_anonymous, the_user, the_message, the_context, the_total_bits_ever)
signal channel_point_redeem(the_reward, the_user, the_user_input, the_reward_status)
signal incoming_whisper(the_sender, the_message)

func _init():
	add_child(Ping_Timer)
	Ping_Timer.autostart = false
	ConnectDelay.one_shot = false
	Ping_Timer.wait_time = 59.0
	Ping_Timer.connect("timeout", self, "_on_Ping_Timer_timeout")
	websocket.verify_ssl = true
	user_regex.compile("(?<=!)[\\w]*(?=@)")
	if delay_connection:
		add_child(ConnectDelay)
		ConnectDelay.autostart = true
		ConnectDelay.one_shot = true
		ConnectDelay.wait_time = delay_seconds
		ConnectDelay.connect("timeout", self, "_on_ConnectDelay_timeout")
	else:
		make_connections()

func load_creds(fileloc):
	var file = File.new()
	if not file.file_exists(fileloc):
		print("no pubsub cred")
		return # File does not exist
	file.open(fileloc, File.READ)
	var content = file.get_as_text()
	content = parse_json(content)
	the_auth = String(content["the_auth"])
	the_listener = String(content["the_listener"])
	the_channel = String(content["the_channel"])
	file.close()

func _ready():
	pass
	load_creds(cred_file)
	
func make_connections():
	websocket.connect("data_received", self, "data_received")
	websocket.connect("connection_established", self, "connection_established")
	websocket.connect("connection_closed", self, "connection_closed")
	websocket.connect("server_close_request", self, "sever_close_request")
	websocket.connect("connection_error", self, "connection_error")
	connect_to_twitch()

func _process(delta):
	if(websocket.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED):
		websocket.poll()
	
func _input(event):
	if event.is_action_pressed("ui_accept"):
		emit_signal("incoming_bits",20)
		
func connect_to_twitch() -> void:
	var err = websocket.connect_to_url(SOCKET_URL)
	if err != OK:
		print("Unable to connect")
		set_process(false)

func authenticate_oauth(nick : String, token : String) -> void:
	websocket.get_peer(1).set_write_mode(WebSocketPeer.WRITE_MODE_TEXT)
	send("PASS " + ("" if token.begins_with("oauth:") else "oauth:") + token, true)
	send("NICK " + nick.to_lower())
	request_caps()

func request_caps(caps : String = "twitch.tv/commands twitch.tv/tags twitch.tv/membership") -> void:
	send("CAP REQ :" + caps)

# Sends a String to Twitch.
func send(text : String, token : bool = false) -> void:
	websocket.get_peer(1).put_packet(text.to_utf8())
	if(OS.is_debug_build()):
		if(!token):
			pass
			#print("< " + text.strip_edges(false))
		else:
			print("< PASS oauth:******************************")

func data_received() -> void:
	var payload = websocket.get_peer(1).get_packet().get_string_from_utf8()
	payload = payload.replace("\\", "")
	payload = payload.replace('"message":"{', '"message":{')
	payload = payload.replace('}"}}', '}}}')
	payload = parse_json(payload) 
	#print(payload)
	if payload["type"] == "MESSAGE":
		if payload["data"]["topic"] == "channel-points-channel-v1." + the_channel:
			proc_channel_points(payload)
		elif payload["data"]["topic"] == "channel-bits-events-v2." + the_channel:
			proc_bits(payload)
		elif payload["data"]["topic"] == "channel-subscribe-events-v1." + the_channel:
			proc_subs(payload)
		elif payload["data"]["topic"] == "whispers." + the_channel:
			proc_whisper(payload)
		# Mod action functions not created yet. 
#		elif payload["data"]["topic"] == "chat_moderator_actions." + <user ID> + "." + the_channel:
#			print("mod")
	
func connection_established(protocol : String) -> void:
	print_debug("Pubsub connected to Twitch.")
	emit_signal("twitch_connected")
	authenticate_oauth(the_listener, "oauth:" + the_auth)
	send('{"type": "LISTEN","nonce": "80084","data": {"topics": ["channel-bits-events-v2.' + the_channel + '"],"auth_token": "' + the_auth + '"}}')
	send('{"type": "LISTEN","nonce": "80085","data": {"topics": ["channel-points-channel-v1.' + the_channel + '"],"auth_token": "' + the_auth + '"}}')
	send('{"type": "LISTEN","nonce": "80086","data": {"topics": ["channel-subscribe-events-v1.' + the_channel + '"],"auth_token": "' + the_auth + '"}}')
	# Uncomment the lines below and enter appropriate user id's if you want to listen to moderation actions and whispers. See docs: https://dev.twitch.tv/docs/pubsub#topics
#	send('{"type": "LISTEN","nonce": "80087","data": {"topics": ["chat_moderator_actions.' + <user ID> + '.' + the_channel + '"],"auth_token": "' + the_auth + '"}}')
#	send('{"type": "LISTEN","nonce": "80088","data": {"topics": ["automod-queue.' + <moderator_id> + '.' + the_channel + '"],"auth_token": "' + the_auth + '"}}')
#	send('{"type": "LISTEN","nonce": "80089","data": {"topics": ["user-moderation-notifications.' + <current_user_id> + '.' + the_channel + '"],"auth_token": "' + the_auth + '"}}')
#	send('{"type": "LISTEN","nonce": "80090","data": {"topics": ["whispers.' + the_channel + '"],"auth_token": "' + the_auth + '"}}')
	send('{"type": "PING"}')
	Ping_Timer.start()
	
func connection_closed(was_clean_close : bool) -> void:
	if(twitch_restarting):
		print_debug("PubSub Reconnecting to Twitch")
		emit_signal("twitch_reconnect")
		connect_to_twitch()
		yield(self, "twitch_connected")
		twitch_restarting = false
	else:
		print_debug("PubSub Disconnected from Twitch.")
		emit_signal("twitch_disconnected")
		connect_to_twitch()
		
func connection_error() -> void:
	print_debug("PubSub Twitch is unavailable.")
	emit_signal("twitch_unavailable")

func server_close_request(code : int, reason : String) -> void:
	pass

func _on_Ping_Timer_timeout():
	send('{"type": "PING"}')

func proc_channel_points(payload):
	pass
	var m_data = payload["data"]["message"]
	if m_data["type"] == "reward-redeemed":
		var r_data = m_data["data"]["redemption"]
		var the_user = r_data["user"]["display_name"]
		var the_reward = r_data["reward"]["title"]
		var the_user_input = ""
		var the_reward_status = ""
		if r_data.has("user_input"):
			the_user_input = r_data["user_input"]
		if r_data.has("status"):
			the_reward_status = r_data["status"]
		print(the_user + ", redeemed the reward: " + the_reward + ", the status is: " + the_reward_status + " and they say: " + the_user_input)
		emit_signal("channel_point_redeem", the_reward, the_user, the_user_input, the_reward_status)

func proc_subs(payload):
	var m_data = payload["data"]["message"]
	var is_gift = "false"
	var the_context = ""
	var the_purchaser = ""
	var the_recipient = ""
	var the_sub_plan = ""
	var the_total_months = ""
	var the_streak_months = ""
	var the_multi_month_buy = ""
	
	if m_data.has("is_gift"):
		is_gift = m_data["is_gift"]
	if m_data.has("context"):
		the_context = m_data["context"]
	if m_data.has("display_name"):
		the_purchaser = m_data["display_name"]
	if m_data.has("recipient_display_name"):
		the_recipient = m_data["recipient_display_name"]
	if m_data.has("sub_plan"):
		the_sub_plan = m_data["sub_plan"]
	if m_data.has("cumulative_months"):
		the_total_months = m_data["cumulative_months"]
	if m_data.has("streak_months"):
		the_streak_months = m_data["streak_months"]
	if m_data.has("multi_month_duration"):
		the_multi_month_buy = m_data["multi_month_duration"]
	
	print("Is a gift: " + String(is_gift) + ",")
	print("Context: " + the_context + ",")
	print("Purchaser: " + the_purchaser + ",")
	print("Recipient: " + the_recipient + ",")
	print("Sub Plan: " + String(the_sub_plan) + ",")
	print("Cumulative Months: " + String(the_total_months) + ",")
	print("Streak: " + String(the_streak_months) + ",")
	print("Multi-Month Buy: " + String(the_multi_month_buy) + ".")
	emit_signal("incoming_subs", is_gift, the_context, the_purchaser, the_recipient, the_sub_plan, the_total_months, the_streak_months, the_multi_month_buy)

func proc_bits(payload):
	var m_data = payload["data"]["message"]["data"]
	var is_anonymous = false
	var the_user = "Anonymous"
	var the_bits = 0
	var the_message = ""
	var the_context = ""
	var the_total_bits_ever = ""
	
	if m_data.has("is_anonymous"):
		is_anonymous = m_data["is_anonymous"]
	if m_data.has("user_name"):
		the_user = m_data["user_name"]
	if m_data.has("bits_used"):
		the_bits = m_data["bits_used"]
	if m_data.has("chat_message"):
		the_message = m_data["chat_message"]
	if m_data.has("context"):
		the_context = m_data["context"]
	if m_data.has("total_bits_used"):
		the_total_bits_ever = m_data["total_bits_used"]
		
	print("Anonymous: " + String(is_anonymous) + ",")
	print("Purchaser: " + the_user + ",")
	print("Bits: " + String(the_bits) + ",")
	print("Message: " + String(the_message) + ",")
	print("Context: " + String(the_context) + ",")
	print("Total bits spent: " + String(the_total_bits_ever) + ".")
	emit_signal("incoming_bits", the_bits, is_anonymous, the_user, the_message, the_context, the_total_bits_ever)

func proc_whisper(payload):
	var m_data = parse_json(payload["data"]["message"])
	var whisp_data = parse_json(m_data["data"])
	var the_sender = whisp_data["tags"]["display_name"]
	var the_message = whisp_data["body"]
	print(the_sender + " whispered: " + the_message)
	emit_signal("incoming_whisper", the_sender, the_message)

func proc_mods(payload):
	pass # I have not yet written a mod action processor yet.

func _on_ConnectDelay_timeout():
	pass # Replace with function body.
	make_connections()
