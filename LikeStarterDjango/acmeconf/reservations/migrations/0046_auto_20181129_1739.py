# Generated by Django 2.0.3 on 2018-11-29 17:39

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('reservations', '0045_auto_20181129_1730'),
    ]

    operations = [
        migrations.AlterField(
            model_name='event',
            name='crowd_pic',
            field=models.ImageField(default='pic_folder/None/no-img.jpg', upload_to='MEDIA_ROOT'),
        ),
    ]
