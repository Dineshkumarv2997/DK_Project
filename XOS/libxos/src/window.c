
/*
 * libXOS
 * Rudimentary custom C library for xOS
 * Copyright (C) 2017 by Omar Mohammad.
 *
 * MIT license
 */

#include <xos.h>
#include "component.h"

// xos_find_free_window:
// Finds a free window

xos_window xos_find_free_window()
{
	xos_window ret;

	for(ret = 0; ret < LIBXOS_MAX_WINDOWS; ret++)
	{
		if(libxos_windows[ret].present == 0)
			goto success;
	}

	// failure..
	return -1;

success:
	return ret;
}

// xos_find_free_component:
// Finds a free component

xos_component xos_find_free_component(xos_window window)
{
	xos_component ret;

	for(ret = 0; ret < LIBXOS_MAX_COMPONENTS; ret++)
	{
		if(libxos_windows[window].components[ret << 8] == 0)
			goto success;
	}

	return -1;

success:
	return ret;
}

// xos_create_window:
// Creates a window that can be used as a container for widgets

xos_window xos_create_window(int16_t x, int16_t y, int16_t width, int16_t height, uint16_t flags, const char *title)
{
	xos_window ret = xos_find_free_window();
	if(ret == -1)
		return -1;

	uint8_t *components = malloc(LIBXOS_MAX_COMPONENTS * 256);	// each component is 256 bytes

	// create the window
	int32_t k_window = k_create_window(x, y, width, height, flags, title);

	libxos_windows[ret].present = 1;
	libxos_windows[ret].k_window = k_window;
	libxos_windows[ret].color = WINDOW_COLOR;
	libxos_windows[ret].components = components;

	return ret;
}

// xos_destroy_window:
// Destroys a window

void xos_destroy_window(xos_window window)
{
	if(window >= LIBXOS_MAX_WINDOWS || libxos_windows[window].present != 1)
		return;

	// free the component memory
	free(libxos_windows[window].components);

	// destroy the window itself
	k_destroy_window(libxos_windows[window].k_window);

	// and destroy the handle
	libxos_windows[window].present = 0;
	libxos_windows[window].k_window = 0;
	libxos_windows[window].color = 0;
	libxos_windows[window].components = 0;
}

// xos_set_color:
// Sets a window oclor

void xos_set_color(xos_window window, uint32_t color)
{
	libxos_windows[window].color = color;
}

// xos_lock:
// Prevents a window from being redrawn

void xos_lock(xos_window window)
{
	libxos_windows[window].lock = 1;
}

// xos_unlock:
// Allows a window to be redrawn

void xos_unlock(xos_window window)
{
	libxos_windows[window].lock = 0;
}

// xos_redraw:
// Redraws a window

void xos_redraw(xos_window window)
{
	if(libxos_windows[window].lock)		// if locked, ignore
		return;

	uint8_t *components = libxos_windows[window].components;
	uint8_t *components_end = components + (LIBXOS_MAX_COMPONENTS * 256);

	k_clear(libxos_windows[window].k_window, libxos_windows[window].color);

	while(components < components_end)
	{
		if(components[0] == COMPONENT_NONE)
			goto loop_again;

		else if(components[0] == COMPONENT_LABEL)
			xos_redraw_label(window, (xos_label_t*)components);

		else if(components[0] == COMPONENT_BUTTON)
			xos_redraw_button(window, (xos_button_t*)components);

		else if(components[0] == COMPONENT_VSCROLL)
			xos_redraw_vscroll(window, (xos_vscroll_t*)components);

		else if(components[0] == COMPONENT_CANVAS)
			xos_redraw_canvas(window, (xos_canvas_t*)components);

	loop_again:
		components += 256;
	}

	k_redraw(libxos_windows[window].k_window);
}

// xos_fill_rect:
// Fills a solid rectangle

void xos_fill_rect(xos_window window, int16_t x, int16_t y, int16_t width, int16_t height, uint32_t color)
{
	if(libxos_windows[window].present != 1)
		return;

	if(!width || !height)
		return;

	// get window info
	k_window window_info;
	k_get_window(libxos_windows[window].k_window, &window_info);

	if(x + width > window_info.width || y + height > window_info.height)
		return;

	// get pixel offset
	uint32_t *canvas;
	canvas = (uint32_t*)k_pixel_offset(libxos_windows[window].k_window, x, y);

	int16_t x2, y2;

	x2 = 0;
	y2 = 0;

	while(y2 < height)
	{
		while(x2 < width)
		{
			canvas[x2] = color;
			x2++;
		}

		x2 = 0;
		y2++;
		canvas += window_info.width;
	}
}



