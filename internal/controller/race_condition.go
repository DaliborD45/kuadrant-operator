package controllers

import (
	"context"

	"golang.org/x/sync/errgroup"
)

func Foo() error { return nil }
func Bar() error { return nil }
func Baz() error { return nil }

func Run(ctx context.Context) error {
	err := Foo()
	if err != nil {
		return err
	}

	wg, ctx := errgroup.WithContext(ctx)
	wg.Go(func() error {
		err = Baz()
		if err != nil {
			return err
		}

		return nil
	})
	wg.Go(func() error {
		err = Bar()
		if err != nil {
			return err
		}

		return nil
	})

	return wg.Wait()
}
