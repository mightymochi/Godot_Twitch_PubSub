# Godot Twitch PubSub
If you have ever wanted to connect your Godot application to Twitch channel points, bits, and subscriptions; this is some code that can help you.

## Step 1
Create a Twitch Application: https://dev.twitch.tv/docs/authentication/register-app

## Step 2
Generate Twitch oauth tokens from your app: https://twitchapps.com/tokengen/ using the required scopes: https://dev.twitch.tv/docs/pubsub#topics

## Step 3
Create your credential json file:

```
{"the_auth":"<your token>", "the_listener":"<your app name>", "the_channel":"<your channel id>",}
```

OR save the info for variables in the script.

## Step 4
In your Godot project, attach the https://github.com/mightymochi/Godot_Twitch_PubSub/blob/main/pubsub.gd script to a Node2D

## Step 5
Enter the file path of your credentials into the Cred File, or enter the information into the individual variable entries.

![pubsub variables](https://github.com/mightymochi/Godot_Twitch_PubSub/blob/main/pub_sub_variables.PNG)

## Step 6 
Set connection delay to desired time. 

## Step 7
Connect your custom code to the signals.

![pubsub signals](https://github.com/mightymochi/Godot_Twitch_PubSub/blob/main/pubsub_signals.PNG)

## Step 8
Run program. If everything was set up and entered properly you should be able to get a feed of bits, points, and subs.
