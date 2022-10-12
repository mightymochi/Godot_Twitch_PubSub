# Godot Twitch PubSub
Connect your Godot app to the Twitch PubSub

If you have ever wanted to connect your Godot application to Twitch channel points, bits, and subscriptions, this is some code that can help you.

## Step 1
Create a Twitch Application: https://dev.twitch.tv/docs/authentication/register-app

## Step 2
Generate Twitch oauth tokens from your app: https://twitchapps.com/tokengen/ using the required scopes: https://dev.twitch.tv/docs/pubsub#topics

## Step 3
Create your credential file:

```
{"the_auth":"<your token>", "the_listener":"<your app name>", "the_channel":"<your channel>",}
```

OR save the info for variables in the script.

## Step 4
In your Godot project, attached the https://github.com/mightymochi/Godot_Twitch_PubSub/blob/main/pubsub.gd script to a Node2D

## Step 5
Enter the file path of your credentials into the Cred File, or enter the information into the individual variable entries.

## Step 6 
Set connection delay to desired time. 

## Step 7
Connect your custom code to the signals.

## Step 8
Run program. If everyting was set up and entered properly you should be able to get a feed of bits, points, and subs.
