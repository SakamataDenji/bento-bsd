import discord
from discord.ext import commands
import random

# --- CONFIGURACIÓN BÁSICA DEL BOT ---
intents = discord.Intents.all()
bot = commands.Bot(command_prefix="lunaria!", intents=intents, help_command=None)

# --- EVENTO: Bot listo ---
@bot.event
async def on_ready():
    print(f"🌑 Nyra has awakened... Connected as {bot.user.name}")

# --- COMANDO: sabiduría mística ---
@bot.command()
async def wisdom(ctx):
    lines = [
        "Even void can return something.",
        "All data is a spell waiting to be cast.",
        "Modules are fragments of the soul, split but eternal.",
        "Syntax isn't written — it's conjured.",
        "The REPL is your cauldron; stir it wisely."
    ]
    await ctx.send(f"🔮 {random.choice(lines)}")

# --- COMANDO: bienvenida manual (útil para pruebas) ---
@bot.command()
async def welcome(ctx, member: discord.Member = None):
    member = member or ctx.author
    embed = discord.Embed(
        title="🌙 A new star rises...",
        description=f"Welcome to **Lunaria**, {member.mention}!\nLet the code guide you through the void.",
        color=0x9e91ff
    )
    embed.set_footer(text="Nyra, Guardian of the Grimoire")
    await ctx.send(embed=embed)

# --- COMANDO: ayuda personalizada ---
@bot.command()
async def help(ctx):
    embed = discord.Embed(title="📜 Nyra's Grimoire of Commands", color=0xaab6ff)
    embed.add_field(name="lunaria!wisdom", value="Receive a cryptic line of code-sorcery.", inline=False)
    embed.add_field(name="lunaria!welcome [@user]", value="Manually invoke the welcome ritual.", inline=False)
    embed.set_footer(text="More spells soon to be discovered...")
    await ctx.send(embed=embed)

# --- INICIO DEL BOT ---
# Para correr el bot, reemplaza 'YOUR_BOT_TOKEN_HERE' con tu token real
bot.run()
